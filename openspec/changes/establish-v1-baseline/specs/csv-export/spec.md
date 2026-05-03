## ADDED Requirements

### Requirement: Default CSV format with null sentinel

The system SHALL produce CSV with header `row,col,code` followed by one row per `(row, col)` position in the inferred or declared layout. Missing cells, unreadable cells, and validator-rejected cells SHALL render as the literal string `null` in the `code` column. Blank values SHALL NEVER appear. Output SHALL be UTF-8 encoded with `\n` line endings.

#### Scenario: 9×9 fixed layout always emits 81 data rows

- **WHEN** exporting a `.fixed(9, 9)` scan with provenance OFF
- **THEN** the output has 1 header row + 81 data rows = 82 lines total

#### Scenario: Empty cell renders as null

- **WHEN** a cell at (1, 2) has `status = .empty`
- **THEN** the corresponding CSV row is `1,2,null`

### Requirement: Optional provenance column

The system SHALL append a `status` column when `@AppStorage` key `includeProvenanceColumn` is `true` (CEL default). Status values:

| Status string | Meaning |
|---|---|
| `decoded` | Vision/ZXing decode passed validator, no edit |
| `edited` | `userOverride` set on a decoded cell |
| `manual` | `userAdded == true` (user populated empty cell) |
| `empty` | declared/inferred position with no detection |
| `unreadable:decode_failed` | bbox detected, no payload extractable |
| `unreadable:rejected(<payload>)` | decoded but failed validator |
| `unreadable:low_confidence(<payload>)` | decoded with low confidence |
| `decoded:outlier` | decoded code outside the declared layout, kept as outlier |
| `discarded` | unplaced detection the user explicitly discarded |

#### Scenario: Provenance ON includes status column

- **WHEN** `includeProvenanceColumn` is `true` and an edited cell at (1, 3) has override `"B00042"`
- **THEN** the row is `1,3,B00042,edited`

#### Scenario: Discarded detection preserved with status

- **WHEN** the user discarded an unplaced detection with payload `"Z99999"` and provenance is ON
- **THEN** the CSV contains a row `null,null,Z99999,discarded`

### Requirement: Outlier rows render with null row/col

The system SHALL emit kept-as-outlier cells (`row = -1, col = -1`) as CSV rows with `row=null, col=null` and the decoded payload. Provenance status `decoded:outlier`. Outlier rows SHALL appear after all in-grid rows.

#### Scenario: Outlier appears after grid rows

- **WHEN** a 9×9 scan has 81 grid cells plus one kept outlier with payload `"X12345"`
- **THEN** the CSV has 81 grid rows followed by `null,null,X12345,decoded:outlier` (or `null,null,X12345` with provenance OFF)

### Requirement: Deterministic ordering

The system SHALL sort grid rows ascending by `row`, then ascending by `col`. Outlier and discarded rows SHALL appear after all grid rows, in detection order.

#### Scenario: Sorted output

- **WHEN** exporting cells `[(2,1), (1,3), (1,1)]`
- **THEN** the data rows appear in order `(1,1)`, `(1,3)`, `(2,1)`

### Requirement: Filename and user actions

The system SHALL generate filenames of the form `DataMatrix_<ISO8601timestamp>.csv` (e.g. `DataMatrix_2026-04-26T143022.csv`). The system SHALL provide three user actions in `ResultView`:
- **Copy CSV**: writes the CSV string to `UIPasteboard.general`
- **Share**: presents `UIActivityViewController` with the CSV as a file attachment
- **Save to Files**: presents `UIDocumentPickerViewController`

#### Scenario: Copy puts CSV on the clipboard

- **WHEN** the user taps "Copy CSV"
- **THEN** `UIPasteboard.general.string` equals the generated CSV
