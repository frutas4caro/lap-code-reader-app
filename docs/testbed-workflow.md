# Testbed Workflow

## Corpus Layout

`TestImages/` contains a mix of **bundles** (preferred) and **bare images**
(legacy). The TestBed CLI auto-detects which is which:

```
TestImages/
  46__sparsed_missing/                 # bundle (preferred format)
    input.jpg
    expected.csv
    detected.json                      # optional; populated by app exports
    metadata.json
    annotated.jpg                      # optional reference render
  100__dense_rotated.jpg               # bare image (legacy)
```

A directory containing both `input.jpg` and `expected.csv` is a bundle.
Anything else at the top level is treated as a bare image.

## Bundle Format

```
bundle-name/
  input.jpg          # full-resolution original
  expected.csv       # ground truth, in the v1 CSV schema (provenance OFF)
                     # — `null` for empty/unreadable, every (row,col) listed
  detected.json      # raw Vision/ZXing output (payloads, bboxes, confidence)
                     # — present when the bundle was exported by the app;
                     #   absent for hand-built seed bundles
  metadata.json      # capture context — see schema below
  annotated.jpg      # optional visual reference; not asserted on
```

`metadata.json`:
```json
{
  "schemaVersion": 1,
  "source": "app-export" | "seed-from-reference-pipeline" | "manual",
  "captureDevice": "iPhone 15 Pro",
  "iosVersion": "18.4",
  "appVersion": "1.0.3",
  "validatorRegex": "^[A-Z]\\d{5}$",
  "layoutMode": "fixed" | "auto",
  "layoutRows": 9,
  "layoutCols": 9,
  "decodedCount": 73,
  "expectedCount": 81,
  "createdAt": "2026-04-26T14:30:22Z",
  "notes": "free-form"
}
```

## Bare Image Convention (legacy)

`<expected_code_count>__<notes>.jpg` — e.g. `12__full_grid.jpg`,
`100__dense_rotated.jpg`. Only the count assertion runs; no per-cell ground
truth is available. New corpus additions should be **bundles**.

## What the Testbed Validates

For each bundle:
1. Pipeline runs without throwing (no `PipelineEvent.failed`)
2. Decoded count ≥ 95% of `expected.csv` non-null entries
3. All decoded payloads match the validator regex (or are correctly placed
   in `.unreadable(.validatorRejected(_))`)
4. Per-cell match: the (row, col) → code mapping matches `expected.csv`
   for ≥ 99% of cells where the user did not subsequently override
5. Inferred grid dimensions equal the declared layout (when `layoutMode == "fixed"`)
6. Annotation renders without error
7. Outlier handling: outliers in `expected.csv` (row/col = null) appear in
   actual output

For each bare image:
1. Decoded count matches `<expected_code_count>` (filename)
2. All decoded payloads match the **default** validator regex
3. Annotation renders without error

## Running

```
swift run TestBed TestImages/
```

Output per item:
```
✓ 46__sparsed_missing/      — 46/46 decoded, grid 9×9, cell-match 100%
✗ 100__dense_rotated.jpg    — 87/100 decoded (87%), grid inference failed
```

Summary: X/Y items fully passing.

## Pass Thresholds

- Per-PR (CI): no regression — items previously passing must still pass.
- Phase advance (per `docs/implementation-plan.md` Phase 6):
  - **≥ 95%** image-level decode-count match across the corpus
  - **≥ 99%** per-cell decode reliability across all bundles
  - Both gates must hold; failing either blocks release.

## Corpus-Growth Ritual

Every `TestCaseBundle` exported from a real scan during development is a
candidate for `TestImages/`. Drop the bundle directory into `TestImages/`,
optionally update a `CORPUS.md` note describing what edge case it covers,
commit. The testbed picks it up on the next run. This is how production
edits feed the regression suite.

Avoid near-duplicates. New bundles should expose a failure mode the
existing corpus does not cover (different lighting, rotation, missing
pattern, density, validator-rejected examples, etc.).
