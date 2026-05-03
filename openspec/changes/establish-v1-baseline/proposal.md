## Why

The project has a thorough charter and seven design docs but `openspec/specs/` is empty, so there is no machine-checkable contract for what each capability promises. Implementation cannot begin under spec-driven workflow until the v1 baseline capabilities are captured as specs. This change establishes that baseline and folds in five design decisions made during exploration that the existing docs do not yet reflect.

## What Changes

- Carve the v1 system into eight capability specs (see Capabilities below).
- **Split annotation into two distinct artifacts**: a SwiftUI live overlay driven directly by `cells` (drives ResultView, reflects edits in real time) and a baked `UIImage` produced lazily on demand for share / save / history thumbnail / TestCaseBundle. `PipelineEvent.annotated` becomes the *initial* bake, not the source of truth for the in-app view.
- **Unplaced strip UX for outliers and non-decoded codes**: any detection that cannot be confidently assigned to a grid position (spatial outlier, decode-failed bbox, validator-rejected code far from any ideal position) appears in an "Unplaced" strip beside the grid. User actions: place at (row, col), edit payload, keep as outlier (`row=null, col=null`), or discard. **BREAKING vs. existing docs**: collapses the previously ambiguous 2×3 (spatial × semantic) outlier matrix into a single UI affordance.
- **Save button as the edit-end signal**: ResultView gains explicit Save state. The pipeline still auto-persists the original scan at end-of-pipeline; "Save" commits *edits*. TestCaseBundle export is gated on saved state. `metadata.json.edit_count` is derived from final cell state at save time (`count where userOverride != nil OR userAdded == true`) — no event log required.
- **Audit-grade discard semantics**: discarding an unplaced detection keeps a row in the CSV with `row=null, col=null, code=<payload>, status=discarded` (provenance ON) rather than dropping it silently. **BREAKING vs. existing csv-export-spec.md**: adds the `discarded` provenance status and forbids silent removal.
- **Re-validation of historical scans against current regex**: `StoredScan` stores `validatorRegexAtCapture` (immutable, audit) plus the raw decoded payloads with bboxes; cell statuses are *derived* on view by applying the current regex to those payloads. Regex changes propagate to history automatically; the original verdict is recoverable from `validatorRegexAtCapture`. **BREAKING vs. existing architecture.md**: cells become derived, not stored.
- Defer the 700ms "first usable result" target until benchmarks justify a number; specs assert the < 3s end-to-end and < 2s annotation-bake budgets only.

## Capabilities

### New Capabilities
- `barcode-decoding`: Vision + ZXing fallback contract. Inputs (UIImage), outputs (`[RawDetection]` with payload, bbox in UIKit coordinates, confidence, raw bytes when ZXing). Includes the low-result retry heuristic and binary-payload fallback trigger.
- `payload-validation`: Regex-driven partition of raw detections into decoded vs. validator-rejected. Reads regex from `@AppStorage`. Re-validation contract: pure function over raw payloads, applied on view.
- `grid-inference`: Auto and Fixed layout modes, PCA + 1D gap clustering for orientation, ideal-position mapping for fixed mode, outlier production (row=-1, col=-1). Validator-rejected codes are placed by the same logic and surface as `unreadable.validatorRejected`. Emits `[GridCell]` plus an unplaced list.
- `scan-pipeline`: Actor-orchestrated sequencing of decode → validate → infer → annotate(initial-bake) → export → persist. Emits `AsyncStream<PipelineEvent>`. Best-effort, never-abort: only `permissionDenied`, `imageTooLarge`, and true CGImage failure flow through `PipelineEvent.failed`.
- `result-rendering`: The SwiftUI live overlay (color matrix from `annotation-spec.md`), the cell editor (decoded / unreadable / empty / outlier flows), the unplaced strip, and the save-state machine. The baked-image renderer is a sub-capability invoked on demand.
- `csv-export`: Format with `null` sentinel, optional provenance column, the `discarded` status, copy/share/save-to-Files actions, and the deterministic ordering rule (row asc, col asc, then unplaced rows with `row=null,col=null`).
- `scan-storage`: SwiftData `StoredScan` with file-backed photos, derived-cell model (raw payloads + edits stored, statuses computed on view), retention/auto-trim (default 30 days / 1 GB; trim photos only, retain records).
- `test-case-bundles`: TestCaseBundle format, in-app `TestCaseExporter` (gated on saved state), TestBed CLI ingest. Bundle CSV is provenance-OFF regardless of user setting; `metadata.json` includes outlier-resolution counts.

### Modified Capabilities
<!-- None. specs/ is empty. -->

## Impact

- **Affected code**: All v1 modules. Greenfield — no existing implementation to migrate. The deleted `lab-code-reader/` Xcode project files in the working tree will be re-created during implementation.
- **Affected docs**: `architecture.md` (cells-as-derived, live-overlay-vs-baked-image), `annotation-spec.md` (split into live overlay vs bake spec), `csv-export-spec.md` (add `discarded` status), `grid-inference.md` (clarify validator-rejected outlier handling), `testbed-workflow.md` (add outlier-resolution metadata). These updates land as part of implementation, not in this proposal.
- **Dependencies**: ZXingObjC via SPM (Phase 1 task, license verification still pending per charter §9 risk row).
- **No external API or backend impact**: on-device only.
