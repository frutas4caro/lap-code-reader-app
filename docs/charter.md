# Project Charter — DataMatrix Grid Scanner

**Status:** Draft v1
**Date:** 2026-04-26
**Owner:** CEL
**Document type:** Pre-requirements charter (foundation for the requirements document)

---

## 1. Purpose

Bench scientists and lab technicians inventory DataMatrix-coded cryovials by
hand: each vial's code is read off the cap and typed into a spreadsheet,
position by position. For a 9×9 cryovial box that is up to 81 manual entries,
each error-prone and slow, performed at a freezer or biosafety cabinet under
time pressure.

DataMatrix Grid Scanner replaces this workflow with a single iPhone photo:
the app decodes every code in the box, infers the grid layout, presents an
editable visual table, and exports a CSV that lands cleanly in Google Sheets,
Excel, or a LIMS. The user retains full control — every cell is editable,
every failure is explained with an actionable recommendation, and every scan
can be exported as a test case to improve future decoding accuracy.

The app is built by CEL for CEL's cryovial inventory workflow, but ships as a
single CEL-branded App Store binary usable by any lab, logistics team, or
inventory operation that scans grids of DataMatrix codes.

---

## 2. Business Case

| Driver | Today (manual) | With this app |
|---|---|---|
| Time per 9×9 box | ~5–10 minutes | < 30 seconds + review |
| Error rate | High (typos, misreads, position errors) | Low (Vision + ZXing decode + user review) |
| Audit trail | None — final spreadsheet only | Per-cell provenance: `decoded` / `edited` / `manual` / `unreadable:reason` |
| Data quality feedback | None — errors discovered downstream | Edge cases captured as test bundles, fed back into the regression corpus |
| Onboarding cost | New techs trained on naming conventions | App enforces validator regex; CEL defaults preconfigured |

The audit-grade provenance and the test-bundle feedback loop are the two
features that distinguish this from a generic barcode scanner: they make the
output trustworthy enough for inventory-of-record use and they make the
decoder itself improve over time without requiring a backend.

---

## 3. Objectives & Success Criteria

**Primary objectives:**

1. Decode all DataMatrix codes in a single iPhone photo of a cryovial box,
   including under rotation, sparse fill, and partial occlusion.
2. Map each code to its physical position in the box (row, column).
3. Produce an editable visual table and a CSV export compatible with
   Google Sheets, Excel, and Files.
4. Run entirely on-device (no backend, no telemetry, no account required).
5. Improve over time via user-exported test case bundles fed back into a
   regression corpus.

**Quantitative success criteria (v1 release gate):**

| Metric | Target |
|---|---|
| Image-level decode-count match (testbed corpus) | ≥ 95% |
| Per-cell decode reliability across bundles | ≥ 99% |
| End-to-end pipeline (100-code image, iPhone 12) | < 3 s |
| First usable result (grid + CSV ready) | < 700 ms |
| Annotation render (100-code image) | < 2 s |
| Test corpus size at v1 ship | ≥ 10 bundles covering diverse edge cases |
| App Store review pass | First submission |

**Qualitative success criteria:**

- Every failure mode (decode failure, validator rejection, low confidence,
  rotation, blur, exposure) produces an explanation and at least one
  one-tap user action — never a dead-end error screen.
- Zero scans land on a "scan failed" terminal state for transient input
  problems; the user always reaches `ResultView` with editable cells.
- A first-time public user can complete a scan + export without consulting
  documentation.

---

## 4. Scope

### In scope (v1)

- iPhone-only, iOS 17+, single CEL-branded App Store binary
- Single-shot photo capture (custom shutter + torch) and Photos library import
- DataMatrix decoding via Apple Vision with ZXingObjC fallback
- User-configurable payload validator (regex), defaulting to CEL's `^[A-Z]\d{5}$`
- Auto and Fixed-layout grid inference; CEL default `.fixed(9, 9)`,
  per-scan one-tap override
- Per-cell editing, manual cell population, provenance tracking
- CSV export with `null` sentinel and optional `status` (provenance) column
- Annotated-image output with color-coded `CellStatus` rendering
- Local history (SwiftData + file-backed photos) with configurable
  auto-trim (default 30 days / 1 GB; trim photos only, retain records)
- `RemediationAdvisor` providing per-cell and per-scan recommendations
- `TestCaseExporter` producing portable bundles for the regression corpus
- TestBed CLI consuming bundles + bare images from `TestImages/`
- Onboarding (2–3 skippable screens) and Settings UI

### Out of scope (v1)

- Live continuous scanning (deferred to v2 as a separate `LiveScanView`)
- iCloud sync of scan history (deferred to v2)
- Multi-photo stitching for boxes that don't fit in one frame
- Cloud telemetry or backend services of any kind
- Account / authentication / SSO
- Android / iPad / macOS targets
- Direct LIMS integration; CSV is the universal interchange
- Pre-loaded box-format presets beyond the default (CEL standard 9×9)

---

## 5. Stakeholders & Users

| Stakeholder | Role | Interest |
|---|---|---|
| **CEL bench scientists / technicians** | Primary internal users | Fast, accurate cryovial inventory |
| **Public lab / logistics users** | Secondary external users | Generic DataMatrix grid decoding with configurable validation |
| **CEL engineering** | App owner, developer | Single-binary maintainability; regression corpus growth |
| **Apple App Store reviewers** | Gate to distribution | Privacy story, no telemetry, on-device only |
| **Future v2 contributors** | Live-mode, iCloud sync | Architecture must not preclude these |

---

## 6. Deliverables

1. iOS application binary, distributed via App Store
2. CSV export format (specified in `docs/csv-export-spec.md`)
3. Annotated-image output (specified in `docs/annotation-spec.md`)
4. TestCaseBundle format and the TestBed CLI (specified in
   `docs/testbed-workflow.md`)
5. Architecture documentation (`docs/architecture.md`,
   `docs/grid-inference.md`, `docs/vision-api-notes.md`)
6. Implementation plan with phase gates (`docs/implementation-plan.md`)
7. Seed regression corpus in `TestImages/`

---

## 7. Constraints

| Type | Constraint |
|---|---|
| **Platform** | iPhone only, iOS 17+. No iPad/macOS in v1. |
| **Privacy** | No backend, no telemetry, no account. Photos and scan data never leave the device unless the user explicitly exports them. |
| **App Store** | Must pass App Store review; privacy declarations limited to camera, photo library, and Files (all on-device). |
| **Performance** | < 3 s end-to-end on iPhone 12 for a 100-code image; < 2 s annotation alone. |
| **Storage** | Default cap 1 GB scan storage; configurable; auto-trim when exceeded. |
| **Tech stack** | Swift 5.10, SwiftUI, Swift Concurrency only (no completion handlers), MVVM strict. |
| **Build** | Single Xcode scheme, no build flavors, no `#if` conditionals for CEL vs public. |
| **CI** | Xcode Cloud only in v1. |
| **Code quality** | SwiftLint strict mode; no force-unwraps; every public function documented. |
| **Branding** | CEL-branded; defaults are CEL-flavored but every setting is overridable in the UI. |

---

## 8. Assumptions

1. Apple Vision (`VNDetectBarcodesRequest` with `.dataMatrix`) plus ZXingObjC
   fallback can achieve ≥ 95% image-level decode accuracy on the corpus
   without a custom CoreML model in v1.
2. Users will accept manual correction of a small fraction of cells per scan
   (the editor + advisor experience makes this fast).
3. CEL cryovial boxes are the canonical 9×9 layout; non-9×9 layouts are
   handled by per-scan override and `auto` mode.
4. CEL's payload format `[A-Z]\d{5}` is stable; if it changes, only the
   default `@AppStorage` value changes — no code changes required.
5. iPhone 12 is the performance baseline; older devices are best-effort.
6. iOS 17+ adoption is sufficient to ignore older OS versions.
7. The user typically photographs one box per scan; boxes that don't fit in
   one frame are out of scope for v1.
8. No CEL-internal API exists today that the app must integrate with; CSV
   export to Google Sheets is the integration story.
9. Test corpus growth will come primarily from CEL dogfooding; no public
   contribution mechanism is needed in v1.
10. Apple's Enterprise Distribution is not pursued; TestFlight Internal is
    sufficient for CEL pre-release validation.

---

## 9. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Vision decode rate < 95% on real CEL images | Medium | High | ZXing fallback; image-quality preprocessing; user editing closes any remaining gap |
| Grid inference wrong on sparse 9×9 boxes | Medium | High | `.fixed` layout mode forces correct dimensions; addressed in `docs/grid-inference.md` |
| Annotation perf > 2 s on 100-code image | Low | Medium | GPU-backed CIContext; performance test gates phase advance |
| App Store rejection over photo library / camera use | Low | Medium | Standard usage descriptions; on-device only; no telemetry to declare |
| Scan storage bloat on heavy users | Medium | Medium | Auto-trim photos (default 30 days / 1 GB), retain records |
| Misread codes (e.g. `O` vs `0`) silently produce wrong CSV | High | High | Validator regex; rejected codes become `unreadable.validatorRejected` with pre-filled corrective editor; provenance column captures the audit trail |
| User loses unsaved scan when backgrounding | Low | Low | Pipeline cancels on background; user retakes; persistence happens at end of pipeline |
| Test corpus too small to gate releases meaningfully | High at v1 launch | Medium | Corpus-growth ritual: every dogfooding edit becomes a candidate bundle; `CORPUS.md` documents coverage |
| ZXingObjC binary licensing issues on App Store | Low | High | Verify Apache 2.0 / compatible license before Phase 1 SPM integration |

---

## 10. High-Level Architectural Approach

(See `docs/architecture.md` for the full module map and type definitions.)

- **MVVM strict**, with a `ScanPipeline` actor between view-models and
  services. The pipeline emits an `AsyncStream<PipelineEvent>` so the UI
  can render the grid and CSV at ~700 ms while annotation completes in
  the background.
- **Best-effort, never-abort pipeline:** transient failures produce a valid
  `ScanResult` with `unreadable`/`empty` cells and a populated
  `ScanQualityReport`; only true terminal failures (`permissionDenied`,
  `imageTooLarge`, CGImage corruption) flow through `ScanError`.
- **Three-state `CellStatus` enum** (`decoded` / `unreadable(reason)` /
  `empty`) replaces the previous binary code/no-code model so the UI and
  CSV can honestly distinguish "saw a code, couldn't read it" from "no
  vial here."
- **`RemediationAdvisor` protocol** turns failure causes + scan-wide
  context into actionable `Recommendation`s computed lazily at view time
  (so historical scans benefit when the rule set improves).
- **SwiftData with file-backed photos** (paths in the store, blobs on
  disk). `StorageManager` runs auto-trim — default 30 days / 1 GB,
  trimming photos only and preserving records as searchable history.
- **TestCaseBundle** as the canonical regression-corpus format. Same
  format produced by the in-app `TestCaseExporter` and consumed by the
  TestBed CLI, closing the loop from production edits to regression tests.

---

## 11. Milestones

(Per `docs/implementation-plan.md` — durations are rough effort estimates,
not calendar dates.)

| Phase | Deliverable | Gate |
|---|---|---|
| 1 | Settings store, `PayloadValidator`, `BarcodeScanner`, `ScanPipeline` scaffold, TestBed CLI | Testbed runs against seed image |
| 2 | Layout-aware `GridInferencer`, `ImageQualityAnalyzer`, `CellStatus`, unit tests on synthetic grids | Unit-test suite green |
| 3 | `ImageAnnotator` with full color matrix, performance test | 100-code annotation < 2 s |
| 4 | `CSVExporter` with `null` + provenance, share/copy/save, `StorageManager`, `TestCaseExporter` | CSV imports cleanly into Google Sheets |
| 5 | All views (`ScanView`, `ResultView`, `GridView`, `HistoryView`, `SettingsView`, `OnboardingView`), cell editor, advisor surfaces | Manual end-to-end smoke test passes |
| 6 | Corpus seeding, snapshot tests, integration tests, Xcode Cloud workflows, TestFlight, App Store submission | ≥ 95% / ≥ 99% testbed gates met |

---

## 12. Out-of-Charter Items (Tracked for Future Phases)

- v2: Live continuous scanning mode (`LiveScanView`)
- v2: iCloud sync of scan history (SwiftData + CloudKit)
- v1.5: Pinning UI surfaces (the `isPinned` field already ships in v1)
- Future: Multi-photo stitching for oversized boxes
- Future: Additional preset profiles (e.g. logistics, university lab)
- Future: `CORPUS.md` template and per-bundle coverage notes once corpus
  exceeds ~5 bundles
- Future: Settings IA grouping if the field count exceeds ~10

---

## 13. Approval

| Role | Name | Date | Signature |
|---|---|---|---|
| Project Owner (CEL) | _to be signed_ | | |
| Engineering Lead | _to be signed_ | | |

---

*This charter is the authoritative pre-requirements document. Subsequent
artifacts — the requirements document, individual feature specs, and PR
descriptions — should reference this charter by section number when
justifying scope decisions.*
