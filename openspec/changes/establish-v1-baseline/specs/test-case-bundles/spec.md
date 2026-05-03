## ADDED Requirements

### Requirement: TestCaseBundle directory format

The system SHALL define a `TestCaseBundle` as a directory containing:

```
<bundle-name>/
  input.jpg          # full-resolution original (required)
  expected.csv       # ground truth, provenance-OFF format (required)
  detected.json      # raw Vision/ZXing output (optional)
  metadata.json      # capture context (required)
  annotated.jpg      # optional reference render
```

A directory containing both `input.jpg` and `expected.csv` SHALL be recognized as a bundle. The `expected.csv` SHALL use provenance-OFF format regardless of the user's Settings toggle, so bundles round-trip cleanly through the testbed.

#### Scenario: Recognizing a bundle directory

- **GIVEN** a directory `TestImages/foo/` containing `input.jpg` and `expected.csv`
- **WHEN** the TestBed CLI scans `TestImages/`
- **THEN** `TestImages/foo/` is loaded as a bundle

#### Scenario: Directory missing expected.csv is not a bundle

- **GIVEN** a directory `TestImages/bar/` containing only `input.jpg`
- **WHEN** the TestBed CLI scans `TestImages/`
- **THEN** `TestImages/bar/` is not loaded as a bundle (and not loaded as a bare image either; bare images are top-level files only)

### Requirement: metadata.json schema

The system SHALL produce `metadata.json` with at minimum these fields:

```json
{
  "schemaVersion": 1,
  "source": "app-export" | "seed-from-reference-pipeline" | "manual",
  "captureDevice": "<device model>",
  "iosVersion": "<version>",
  "appVersion": "<version>",
  "validatorRegex": "<regex at capture>",
  "layoutMode": "fixed" | "auto",
  "layoutRows": <int>,
  "layoutCols": <int>,
  "decodedCount": <int>,
  "expectedCount": <int>,
  "createdAt": "<ISO8601>",
  "editCount": <int>,
  "outliersResolved": <int>,
  "outliersKept": <int>,
  "outliersDiscarded": <int>,
  "notes": "<free-form>"
}
```

#### Scenario: Required fields present

- **WHEN** `TestCaseExporter` produces a bundle from a saved scan
- **THEN** `metadata.json` contains every field listed above
- **AND** `schemaVersion == 1`

### Requirement: editCount derived from final cell state

The system SHALL compute `editCount` at save time as `count(cells where userOverride != nil OR userAdded == true) + count(unplaced where action != .none)` where `action` is one of place, kept, or discarded. No event log SHALL be required.

#### Scenario: Three edits, one outlier kept

- **GIVEN** a saved scan where the user edited 2 cells, manually added 1 cell, and kept 1 unplaced detection as outlier
- **WHEN** `TestCaseExporter` produces the bundle
- **THEN** `metadata.json.editCount == 4` (2 edited + 1 added + 1 kept)
- **AND** `outliersKept == 1`

### Requirement: TestCaseExporter gated on saved state

The system SHALL disable "Export Test Case" in `ResultView` when the save state is not `saved`. Tapping it in `dirty` state SHALL prompt "Save first?" and SHALL NOT produce a bundle.

#### Scenario: Export disabled in dirty state

- **WHEN** the save state is `dirty`
- **THEN** the "Export Test Case" button is disabled (or, if shown, prompts the user to save first)

### Requirement: TestBed CLI ingests bundles and bare images

The system SHALL provide a `TestBed` SwiftPM CLI target. Running `swift run TestBed TestImages/` SHALL:
- Recursively scan `TestImages/` for bundle directories AND top-level `<count>__<notes>.jpg` bare images.
- For each bundle: assert decoded count ≥ 95% of `expected.csv` non-null entries; assert per-cell `(row, col) → code` match ≥ 99%; assert grid dimensions equal declared layout when `layoutMode == "fixed"`; assert annotation renders without error; assert outlier rows in `expected.csv` appear in actual output.
- For each bare image: assert decoded count matches the count in the filename; assert all decoded payloads match the default validator regex.
- Print one line per item with pass/fail status, then a summary `X/Y passing`.

#### Scenario: Bundle passing all assertions

- **WHEN** `swift run TestBed TestImages/` runs against a bundle with 46 codes in a 9×9 layout
- **AND** the pipeline decodes 46 codes with all (row, col) matches
- **THEN** the line for that bundle reads `✓ <bundle-name> — 46/46 decoded, grid 9×9, cell-match 100%`

#### Scenario: Bare image with mismatched count fails

- **WHEN** running against `100__dense_rotated.jpg` and the pipeline decodes 87 codes
- **THEN** the line reads `✗ 100__dense_rotated.jpg — 87/100 decoded (87%), grid inference failed` (or similar)
- **AND** the summary count of failing items increments

### Requirement: Phase 6 release gates

The system SHALL meet both of these gates before release:
- ≥ 95% image-level decode-count match across the corpus (per-image).
- ≥ 99% per-cell decode reliability across all bundles (cell-level).

Failing either gate SHALL block release.

#### Scenario: Release gate failure on per-cell threshold

- **WHEN** the testbed runs and per-cell match is 98.5%
- **THEN** the run reports failure on the per-cell gate
- **AND** release is blocked

### Requirement: Corpus-growth ritual

Every `TestCaseBundle` exported from a real scan during development SHALL be a candidate for `TestImages/`. Adding a bundle directory to `TestImages/` SHALL be sufficient for the testbed to pick it up on the next run. No manifest file or registration step SHALL be required.

#### Scenario: New bundle picked up automatically

- **WHEN** the developer drops a bundle directory `TestImages/new-edge-case/` into the corpus
- **AND** runs `swift run TestBed TestImages/`
- **THEN** the new bundle appears in the run output without any other configuration
