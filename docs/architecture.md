# Architecture

## Module Map

```
┌─────────────────────────────────────────────────────────────┐
│                          UI Layer                            │
│  ScanView │ ResultView │ GridView │ HistoryView │ SettingsView│
│           │            │ (cell editor) │         │ OnboardingView │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                       ViewModel Layer                        │
│  ScanViewModel │ ResultViewModel │ HistoryViewModel │ SettingsVM│
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    Orchestration Layer                       │
│  ScanPipeline (actor) — sequences services, streams events   │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                       Service Layer                          │
│  ImageQualityAnalyzer  — blur/exposure heuristics            │
│  BarcodeScanner        — Vision decode, ZXing fallback       │
│  PayloadValidator      — regex check (configurable)          │
│  GridInferencer        — geometry, layout-aware              │
│  ImageAnnotator        — draws overlays, labels              │
│  CSVExporter           — builds CSV string, share sheet      │
│  RemediationAdvisor    — failures → user-facing recs         │
│  TestCaseExporter      — packages a scan as a TestCaseBundle │
│  StorageManager        — SwiftData + photo-file lifecycle    │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow (Streaming)

`ScanPipeline.run(image:layout:validator:)` returns an `AsyncStream<PipelineEvent>`:

1. User supplies a `UIImage` (camera capture or Photos picker)
2. `ImageQualityAnalyzer` → `ImageQualityReport` (blur, exposure)
3. `BarcodeScanner` (Vision + ZXing fallback) → `[RawObservation]`
4. `PayloadValidator` partitions into decoded vs. validator-rejected
5. `GridInferencer.infer(codes:, layout:)` → `[GridCell]` with `CellStatus`
6. **`PipelineEvent.partial(ScanResult)` emitted** — UI can render grid + CSV now
7. Parallel fan-out:
   - `ImageAnnotator` → annotated `UIImage` → `PipelineEvent.annotated(_)`
   - `CSVExporter` → CSV string
   - `StorageManager.save(_)` → SwiftData record + photo files
8. `PipelineEvent.complete(ScanResult)` emitted — final, persisted

Best-effort: stages 2–5 produce a `ScanResult` even on poor input (cells become
`unreadable`/`empty`, warnings populate `ScanQualityReport`). Only
`permissionDenied`, `imageTooLarge`, or a true CGImage failure cause
`PipelineEvent.failed(ScanError)`.

`ScanViewModel` consumes the stream on `@MainActor`, updating `@Published`
state as events arrive. The user can edit cells as soon as `.partial` arrives,
~700ms in on a 100-code image.

## Key Types

### Detection & Cells

```swift
struct DetectedCode {
    let payload: String          // e.g. "A00011"
    let boundingBox: CGRect      // normalised 0–1, UIKit top-left origin
    let centroid: CGPoint        // derived from boundingBox
    let confidence: Float
    let rawBytes: Data?          // set when ZXing fallback used
}

enum CellStatus {
    case decoded(DetectedCode)
    case unreadable(reason: UnreadableReason, boundingBox: CGRect?)
    case empty                                      // fixed layout only
}

enum UnreadableReason {
    case validatorRejected(decodedPayload: String)
    case decodeFailed                               // bbox detected, no payload
    case lowConfidence(payload: String, confidence: Float)
}

struct GridCell {
    let row: Int                 // 1-based; nil-able when outlier (see below)
    let col: Int                 // 1-based
    var status: CellStatus
    var userOverride: String?    // user-edited value, takes precedence
    var userAdded: Bool          // true if user manually populated an empty cell
}
```

Outlier handling: in `.fixed` layout mode, codes that don't map to any
declared (row, col) position appear as cells with `row = -1, col = -1` and
`status = .decoded(...)`. They render in the CSV as `row=null, col=null`.
Never silently dropped.

### Layout

```swift
enum BoxLayout: Codable, Equatable {
    case auto                                       // PCA infers row/col counts
    case fixed(rows: Int, cols: Int)                // forced; CEL default = (9, 9)
}
```

### Quality & Recommendations

```swift
struct ScanQualityReport {
    let decodedCount: Int
    let rejectedByValidatorCount: Int
    let expectedCount: Int?                         // present in fixed layout
    let outlierCount: Int
    let principalAxisAngle: Double                  // degrees from horizontal
    let confidenceFloor: Float
    let warnings: [QualityWarning]
}

enum QualityWarning {
    case lowDecodeRatio(decoded: Int, expected: Int)
    case codesRejectedByValidator(count: Int, examples: [String])
    case lowConfidenceReads(count: Int)
    case grossRotation(degrees: Double)
    case outliersDetected(count: Int)
    case imageQualityPoor(reason: ImageQualityReason)
}

enum ImageQualityReason { case blur, underexposed, overexposed }

struct Recommendation {
    let title: String
    let detail: String
    let actions: [RecommendationAction]
}

enum RecommendationAction {
    case retakePhoto
    case enableTorch
    case manuallyEnterCode(row: Int, col: Int, prefill: String?)
    case relaxValidator(suggestedPattern: String?)
    case rotateGrid90
    case adjustGapThreshold
    case useAnyway
}

protocol RemediationAdvisor {
    func adviseCell(_ cell: GridCell, context: ScanResult) -> Recommendation?
    func adviseScan(_ result: ScanResult) -> [Recommendation]
}
```

### Result

```swift
struct ScanResult {
    let id: UUID
    let timestamp: Date
    let sourceImage: UIImage
    var annotatedImage: UIImage?                    // nil until pipeline stage 6
    var cells: [GridCell]                           // mutable: edits, manual adds
    var csv: String                                 // recomputed on edit
    let layoutMode: BoxLayout                       // what was used at scan time
    let validatorRegex: String                      // captured at scan time
    let quality: ScanQualityReport
}

enum ScanError: Error {
    case permissionDenied
    case imageTooLarge
    case decodeFailed(underlying: Error)
    // NOTE: noCodesFound removed — zero codes is a ScanResult with all
    // cells .unreadable or .empty, NOT an error.
}
```

### Pipeline

```swift
actor ScanPipeline {
    func run(image: UIImage,
             layout: BoxLayout,
             validator: PayloadValidator)
        -> AsyncStream<PipelineEvent>
}

enum PipelineEvent {
    case stage(PipelineStage)            // progress label
    case partial(ScanResult)             // cells ready; no annotated image yet
    case annotated(UIImage)              // annotation done
    case complete(ScanResult)            // persisted; final
    case failed(ScanError)               // terminal only
}

enum PipelineStage {
    case analyzingQuality
    case decoding
    case validating
    case inferringGrid
    case annotating
    case exporting
    case saving
}
```

### Persistence

```swift
@Model class StoredScan {
    var id: UUID
    var timestamp: Date
    var sourceImagePath: String          // Application Support/Scans/<uuid>/input.jpg
    var annotatedImagePath: String?      // nil after photo trim
    var cells: [StoredCell]              // payload, row, col, override, source
    var csv: String                      // serialized
    var layoutMode: String               // "auto" or e.g. "9x9"
    var validatorRegex: String           // captured at scan time
    var isPinned: Bool                   // ships v1; full pinning UI in v1.5
}
```

Photos live on disk; SwiftData stores paths only. `StorageManager` runs
auto-trim on launch + after each scan: photos older than the configured
window (default 30 days) or beyond the storage cap (default 1 GB) have their
image files deleted; the SwiftData record is preserved as lightweight history.

### Test Case Bundles

```
bundle/
  input.jpg          # full-res original
  detected.json      # raw Vision/ZXing output (payloads, bboxes, confidence)
  expected.csv       # ground truth = post-edit CSV
  metadata.json      # device, iOS, app version, validator regex,
                     # layout, grid dims, timestamps, edit count
```

`TestCaseExporter` produces these from a `ScanResult` + edit history. The
TestBed CLI reads any subdirectory of `TestImages/` containing `input.jpg`
and `expected.csv` as a bundle. Bare images (legacy convention) keep working
but bundles are the going-forward format.
