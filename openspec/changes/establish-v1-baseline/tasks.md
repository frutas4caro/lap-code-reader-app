## 1. Project Setup

- [ ] 1.1 Re-create Xcode project (`lab-code-reader.xcodeproj`) with iOS 17+ target, Swift 5.10
- [ ] 1.2 Configure SwiftLint strict mode and add to build phase
- [ ] 1.3 Add ZXingObjC via SPM; verify Apache 2.0 license per charter §9
- [ ] 1.4 Create `@AppStorage` keys for `validatorRegex`, `defaultBoxLayout`, `includeProvenanceColumn`, `retentionDays`, `maxStorageBytes`, `gapThresholdMultiplier`, `outlierSigmaThreshold` with CEL-flavored defaults
- [ ] 1.5 Define type stubs from design.md: `RawDetection`, `GridCell`, `CellStatus`, `UnreadableReason`, `BoxLayout`, `ScanResult`, `ScanError`, `PipelineEvent`, `PipelineStage`, `UnplacedDetection`, `StoredScan`, `StoredRawPayload`, `StoredEdit`

## 2. Decoding (capability: barcode-decoding)

- [ ] 2.1 Implement `BarcodeScanner` with Vision primary path
- [ ] 2.2 Add UIKit-top-left coordinate conversion for bounding boxes
- [ ] 2.3 Implement ZXingObjC fallback for nil-payload observations
- [ ] 2.4 Implement low-result heuristic fallback (< 5 results on a clear image triggers full-image ZXing)
- [ ] 2.5 Wire decode-failed → `ScanError.decodeFailed(underlying:)` only on CGImage extraction failure
- [ ] 2.6 Unit tests for each scenario in `specs/barcode-decoding/spec.md`

## 3. Validation (capability: payload-validation)

- [ ] 3.1 Implement `PayloadValidator` reading regex from `@AppStorage`
- [ ] 3.2 Add regex re-compilation on stored value change (Combine or AsyncStream observer)
- [ ] 3.3 Implement `partition(_ detections:) -> (decoded:, rejected:)`
- [ ] 3.4 Implement `revalidate(scan:, regex:) -> [GridCell]` pure function
- [ ] 3.5 Unit tests for each scenario in `specs/payload-validation/spec.md`

## 4. Grid Inference (capability: grid-inference)

- [ ] 4.1 Implement PCA on centroid point cloud (orientation only)
- [ ] 4.2 Implement 1D gap clustering with `gapThresholdMultiplier`
- [ ] 4.3 Implement auto mode (`infer(codes:, layout: .auto)`)
- [ ] 4.4 Implement fixed mode with ideal-position mapping and `outlierSigmaThreshold`
- [ ] 4.5 Implement unplaced list production (spatial outliers, decode-failed bboxes, far-rejected codes)
- [ ] 4.6 Implement `< 3 codes in auto mode` fallback (skip PCA)
- [ ] 4.7 Implement `0 codes` handling (fixed → rows×cols empty cells; auto → empty result)
- [ ] 4.8 Unit tests for each scenario in `specs/grid-inference/spec.md` (synthetic centroid fixtures)

## 5. Pipeline (capability: scan-pipeline)

- [ ] 5.1 Implement `ImageQualityAnalyzer` (variance-of-Laplacian for blur, luminance + clipping)
- [ ] 5.2 Implement `ScanPipeline` actor with `run(...) -> AsyncStream<PipelineEvent>`
- [ ] 5.3 Sequence stages: analyzeQuality → decode → validate → infer → emit `.partial` → fan-out to annotate/export/save → emit `.annotated` → emit `.complete`
- [ ] 5.4 Implement best-effort error handling (only `permissionDenied`/`imageTooLarge`/`decodeFailed` → `.failed`)
- [ ] 5.5 Verify `.partial` arrives before `.annotated`; cell edits during this window are preserved
- [ ] 5.6 Performance benchmark on iPhone 12 hardware (100-code 12MP input): record `.partial`, `.annotated`, `.complete` timings
- [ ] 5.7 Add scenario in `scan-pipeline` spec for `.partial` budget once benchmarked
- [ ] 5.8 Unit + integration tests for each scenario in `specs/scan-pipeline/spec.md`

## 6. Annotation (live overlay + bake)

- [ ] 6.1 Implement live overlay as SwiftUI `Canvas` over source UIImage, driven by `cells` + `unplaced`
- [ ] 6.2 Implement color matrix per `specs/result-rendering/spec.md` (green/blue/orange/yellow/dashed)
- [ ] 6.3 Implement `ImageAnnotator` for baked UIImage output (Core Graphics on GPU-backed CIContext)
- [ ] 6.4 Wire `.annotated(UIImage)` event to initial bake (used as history thumbnail)
- [ ] 6.5 Implement re-bake on demand for share / save-to-Files / TestCaseBundle export
- [ ] 6.6 Performance test: 100-code annotation bake < 2s on iPhone 12
- [ ] 6.7 Snapshot tests for baked output (≤ 1% pixel tolerance)

## 7. CSV Export (capability: csv-export)

- [ ] 7.1 Implement `CSVExporter` with provenance OFF format (header + grid rows + outlier rows + discarded rows)
- [ ] 7.2 Implement provenance ON format with `status` column and the nine status strings
- [ ] 7.3 Implement filename generation (`DataMatrix_<ISO8601>.csv`)
- [ ] 7.4 Implement Copy / Share / Save-to-Files actions in `ResultView`
- [ ] 7.5 Verify CSV imports cleanly into Google Sheets and Excel (manual test)
- [ ] 7.6 Unit tests for each scenario in `specs/csv-export/spec.md`

## 8. Storage (capability: scan-storage)

- [ ] 8.1 Implement SwiftData `StoredScan` model with derived-cell schema (raw payloads + edits, no cells)
- [ ] 8.2 Implement `StorageManager` with photo-file lifecycle (`Application Support/Scans/<uuid>/`)
- [ ] 8.3 Implement auto-trim pass: retentionDays + maxStorageBytes
- [ ] 8.4 Implement on-launch and post-scan auto-trim invocations
- [ ] 8.5 Implement derived-cell view-model: load `rawPayloads` → apply current regex → re-run grid inference → layer edits
- [ ] 8.6 Implement trimmed-scan rendering ("(images cleared)" placeholder, disable bake/export actions)
- [ ] 8.7 Unit + integration tests for each scenario in `specs/scan-storage/spec.md`

## 9. Result Rendering (capability: result-rendering)

- [ ] 9.1 Implement `ScanView` (camera capture + Photos picker + per-scan layout override)
- [ ] 9.2 Implement `ResultView` with stream consumer (renders grid first, image second)
- [ ] 9.3 Implement `GridView` (SwiftUI Table or LazyVGrid)
- [ ] 9.4 Implement cell editor sheet (decoded edit, manual add for empty, validator-rejected pre-fill with highlighted misread chars)
- [ ] 9.5 Implement Unplaced strip with thumbnails, payload, reason, action menu (place / edit / keep / discard)
- [ ] 9.6 Implement save state machine (unsaved → dirty → saving → saved); save button in nav bar
- [ ] 9.7 Implement tap-to-highlight cross-link (grid ↔ overlay) including before initial bake
- [ ] 9.8 Implement scan-level recommendation banner stack
- [ ] 9.9 Implement `RemediationAdvisor` default rules (validator-rejected count → relax suggestion; gross rotation → retake; etc.)
- [ ] 9.10 Implement `HistoryView` and `SettingsView` (all `@AppStorage` keys editable)
- [ ] 9.11 Implement `OnboardingView` (2–3 skippable screens)
- [ ] 9.12 Verify all `ScanError` states have user-facing messages
- [ ] 9.13 Manual end-to-end smoke test on simulator and physical device

## 10. Test Case Bundles (capability: test-case-bundles)

- [ ] 10.1 Implement `TestCaseExporter` producing `input.jpg` + `expected.csv` + `metadata.json` directory
- [ ] 10.2 Implement `editCount` derivation at save time; populate `outliersResolved/Kept/Discarded`
- [ ] 10.3 Gate "Export Test Case" on saved state (disabled in dirty)
- [ ] 10.4 Implement TestBed SwiftPM CLI target
- [ ] 10.5 TestBed: bundle vs bare-image discovery
- [ ] 10.6 TestBed: per-bundle assertions (decode count ≥ 95%, per-cell ≥ 99%, layout match, annotation renders, outliers preserved)
- [ ] 10.7 TestBed: per-bare-image assertions (count match, default-regex match)
- [ ] 10.8 TestBed: pretty-printed pass/fail output + summary line
- [ ] 10.9 Seed `TestImages/46__sparsed_missing/` bundle (manual ground truth)

## 11. Docs Sync (post-implementation)

- [ ] 11.1 Update `docs/architecture.md`: cells-as-derived, live overlay vs baked image, unplaced list
- [ ] 11.2 Update `docs/annotation-spec.md`: split live overlay spec from bake spec
- [ ] 11.3 Update `docs/csv-export-spec.md`: add `discarded` provenance status, unplaced strip semantics
- [ ] 11.4 Update `docs/grid-inference.md`: clarify validator-rejected outlier handling, unplaced list
- [ ] 11.5 Update `docs/testbed-workflow.md`: add `editCount` and outlier-resolution metadata fields

## 12. Release (Phase 6)

- [ ] 12.1 Grow corpus to ≥ 10 bundles covering diverse edge cases (rotation, sparsity, validator-rejected examples, lighting variations)
- [ ] 12.2 Verify testbed gates pass (≥ 95% image-level, ≥ 99% per-cell)
- [ ] 12.3 Set up Xcode Cloud workflows (PR validation, nightly testbed, release upload)
- [ ] 12.4 TestFlight Internal build
- [ ] 12.5 Physical device testing (iPhone, multiple iOS 17+ versions)
- [ ] 12.6 Privacy declarations (camera, photo library, Files; no network)
- [ ] 12.7 App Store Connect metadata + CEL-branded screenshots
- [ ] 12.8 Submit for review

## 13. Archive

- [ ] 13.1 Run `openspec archive establish-v1-baseline` to promote spec deltas into `openspec/specs/`
