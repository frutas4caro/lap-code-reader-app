## Context

DataMatrix Grid Scanner is a greenfield iOS app (iOS 17+, Swift 5.10, SwiftUI, MVVM strict, Swift Concurrency only). The charter (`docs/charter.md`) and seven design docs in `docs/` describe the system in detail; `openspec/specs/` is empty. This change establishes the v1 spec baseline so implementation can begin under spec-driven workflow.

Five design decisions made during exploration are folded in:
1. Live overlay vs. baked image are separate artifacts.
2. Outliers and unplaced detections share one UX (the unplaced strip).
3. Save button is the explicit edit-end signal.
4. Discarded detections leave an audit row in the CSV.
5. Cell statuses are derived from raw payloads + current regex; storage holds payloads, not statuses.

## Goals / Non-Goals

**Goals:**
- A complete v1 spec baseline (eight capabilities) that's testable scenario-by-scenario.
- Resolve the outlier × validator-rejected ambiguity before any code is written.
- Make regex changes propagate to history without a migration.
- Preserve audit-grade provenance: no detection is silently dropped, ever.

**Non-Goals:**
- Specifying the 700ms partial-emit budget (deferred until benchmarked).
- Live continuous scanning, iCloud sync, multi-photo stitching (charter §4 out-of-scope).
- Updating `docs/architecture.md`, `docs/annotation-spec.md`, `docs/csv-export-spec.md`, `docs/grid-inference.md`, `docs/testbed-workflow.md` to reflect the five decisions — those edits land during implementation, not in this proposal.
- Re-creating the deleted `lab-code-reader/` Xcode project (Phase 1 task).

## Decisions

### D1. Cells are derived, not stored

`StoredScan` persists raw decoded payloads (payload + UIKit-space bbox + confidence + raw bytes when ZXing) plus user edits (`userOverride` per (row, col), `userAdded` for manual cells, `discarded` flags). Cell *statuses* (`decoded` / `unreadable.validatorRejected` / etc.) are computed on view by applying the current `validatorRegex` (from `@AppStorage`) against the stored payloads.

`validatorRegexAtCapture` is stored immutably on each `StoredScan` for audit recovery.

**Alternatives considered:**
- Storing cells with statuses, plus an explicit "Re-validate" button. Simpler data model, but regex changes don't propagate; users must remember to re-validate every historical scan.
- Storing both (cells + raw payloads). Redundant; introduces drift risk.

**Why derived wins:** regex changes are low-frequency but high-impact (every historical scan should reflect the new convention immediately when defaults shift). The derivation is cheap (string-regex match over ≤100 payloads).

### D2. Live overlay vs. baked image

Live overlay is a SwiftUI `Canvas` layer composited over the source `UIImage`, driven directly by `cells`. Edits reflect instantly. Baked `UIImage` is produced by `ImageAnnotator` on demand (share, save-to-Files, history thumbnail, TestCaseBundle export). `PipelineEvent.annotated` becomes the *initial* bake (used as history thumbnail).

**Why:** the previous "annotation = single UIImage" model conflated two artifacts and made edited cells go stale until next view-entry. Splitting them eliminates the staleness window and lets GridView's tap-to-highlight work *before* the initial bake completes.

**Risk:** `Canvas` performance on a 12MP image with 100 overlay items. Mitigation: render overlays in normalized coordinate space using `Canvas`, not 100 stacked `Shape` views. Benchmark in Phase 3.

### D3. Unplaced strip collapses the outlier × semantic matrix

Any detection that cannot be confidently placed in a grid cell — spatial outlier, decode-failed bbox, validator-rejected far-from-grid — appears in an unplaced strip beside the grid. User actions per item: place at (row, col), edit payload, keep as outlier, discard.

**Audit guarantee:** discard does **not** drop the row; it produces a CSV row with `row=null, col=null, code=<payload>, status=discarded` (provenance ON). Provenance OFF mode also keeps the row but with `code=null` for unreadable variants.

### D4. Save button is the edit-end signal

Pipeline auto-persists the original scan at end-of-pipeline (charter §10). "Save" commits user *edits* on top. ResultView's save state machine: `unsaved` (post-pipeline, no edits) → `dirty` (after first edit) → `saving` → `saved`. TestCaseBundle export is disabled in `dirty` state; tapping it offers "Save first?".

`metadata.json.edit_count` = `count(cells where userOverride != nil OR userAdded == true) + count(unplaced where action != .none)` at save time. No event log.

### D5. Eight capability cuts

| Capability | Why a separate spec |
|---|---|
| `barcode-decoding` | Vision + ZXing fallback contract is independent of layout, validation, UI |
| `payload-validation` | Pure regex partition; reused by pipeline AND historical re-validation |
| `grid-inference` | Geometric algorithm with two layout modes; testable on synthetic centroid data |
| `scan-pipeline` | Orchestration contract (`PipelineEvent` stream, best-effort guarantee) |
| `result-rendering` | Live overlay + cell editor + unplaced strip + save state |
| `csv-export` | Format spec (null sentinel, provenance, ordering) — round-trips via TestBed |
| `scan-storage` | Persistence + retention + derived-cell model |
| `test-case-bundles` | Bundle format + exporter + testbed ingest, owned end-to-end |

Annotation is split between `result-rendering` (live overlay) and a sub-section of `scan-pipeline` / `csv-export` (the bake-out). Settings are not a separate capability — they're cross-cutting `@AppStorage` values referenced by `payload-validation`, `grid-inference`, and `scan-storage`.

## Risks / Trade-offs

- **[Derived-cell model on heavy edits]** → If a user edits 50 cells on a historical scan, every view recomputes. Mitigation: cache derived cells per (scan-id, regex-hash) in memory; invalidate on regex change or edit.
- **[Canvas overlay perf at 100 codes]** → 12MP image with 100 stroked rects + 100 text labels could drop frames. Mitigation: benchmark in Phase 3; if needed, pre-rasterize overlay paths into a single CGLayer and only re-render the deltas on edit.
- **[Unplaced strip discoverability]** → Users may not notice the strip and miss outliers. Mitigation: scan-level recommendation banner ("3 codes couldn't be placed — review them") that scrolls the strip into view.
- **[Discard provenance leaks PII-ish data]** → If a code is discarded because it's not in the box, its payload still appears in the CSV. Mitigation: this is the audit-grade tradeoff the charter explicitly endorses (§2 audit trail row); document clearly in the user-facing discard sheet.
- **[Spec count creep]** → Eight capabilities is a lot. Mitigation: keep specs requirement-focused (WHAT, not HOW); design.md absorbs cross-cutting decisions so specs stay narrow.

## Migration Plan

Greenfield — no migration. Implementation order matches `docs/implementation-plan.md` Phases 1–6, with the spec deltas providing the acceptance criteria for each phase gate.

## Open Questions

1. **700ms partial-emit budget** — deferred until benchmarked on iPhone 12 hardware. Spec leaves this unspecified; if benchmarks land before Phase 1 closes, add a scenario to `scan-pipeline`.
2. **Re-validation cache invalidation granularity** — per-scan or global? Decide during Phase 4 storage implementation.
3. **History thumbnail refresh** — does the initial bake stay forever, or re-bake when a historical scan is edited? Leaning re-bake on save; spec leaves this for the storage requirement to pin down.
