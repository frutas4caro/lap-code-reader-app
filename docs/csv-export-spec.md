# CSV Export Specification

## Format (default — provenance off)

```
row,col,code
1,1,A00011
1,2,null
1,3,B00042
2,1,null
2,2,C00017
```

- Header row always present: `row,col,code`
- Missing cells, unreadable cells, and rejected codes all render as the
  literal string `null` in the `code` column. **Never blank.**
- Sorted: ascending by row, then col
- One row per (row, col) position in the inferred or declared layout — for
  a 9×9 box the CSV always has **81 rows** plus the header
- Outlier cells (detected codes not matching any (row, col) in fixed mode)
  appear with `row=null, col=null` so they aren't silently dropped
- Line endings: `\n` (Unix)
- Encoding: UTF-8

## Format (with provenance — Settings toggle ON)

CEL default is ON. A fourth column `status` is appended:

```
row,col,code,status
1,1,A00011,decoded
1,2,null,empty
1,3,B00042,edited
2,1,null,unreadable:decode_failed
2,2,null,unreadable:rejected(AOO011)
2,3,X12345,manual
null,null,Z99999,decoded:outlier
```

`status` values:
- `decoded` — Vision/ZXing decode passed validator
- `edited` — `userOverride` was set on a decoded cell
- `manual` — `userAdded == true` (user populated an empty cell)
- `empty` — declared/inferred position with no detection
- `unreadable:decode_failed` — bbox detected, no payload extractable
- `unreadable:rejected(<payload>)` — decoded but failed validator
- `unreadable:low_confidence(<payload>)` — decoded with low confidence
- `decoded:outlier` — decoded code outside the declared layout

## Filename

`DataMatrix_<ISO8601timestamp>.csv` — e.g. `DataMatrix_2026-04-26T143022.csv`

## User Actions (ResultView)

- **Copy CSV** — writes the CSV string to `UIPasteboard`
- **Share** — `UIActivityViewController` with the CSV as a file attachment
  (AirDrop, Mail, Files, Slack, Google Drive upload, etc.)
- **Save to Files** — `UIDocumentPickerViewController`
- **Export Test Case** — produces a `TestCaseBundle` (see
  `docs/testbed-workflow.md`) and shares the bundle directory via the share
  sheet. The CSV inside the bundle uses provenance-OFF format regardless of
  the user's Settings toggle so bundles round-trip cleanly through the
  testbed.

## GridView (visual table)

Display `[GridCell]` as a SwiftUI `Table` or `LazyVGrid` matching the
inferred or declared dimensions:

- `.decoded` cells show the payload (`userOverride ?? code.payload`)
- `.unreadable` cells show an icon + short reason; tap → recommendation sheet
  with action buttons (manual edit, relax validator, retake)
- `.empty` cells show `—` in grey; tap → manual-add editor
- Edited cells (`userOverride != nil`) and manual cells (`userAdded`) render
  in blue
- Tapping any cell highlights the corresponding bbox in the annotated image
  (when annotation is ready; before that, the highlight is in-grid only)

## Google Sheets Import

The `null` sentinel imports cleanly into Google Sheets, Excel, and pandas
without trailing-comma ambiguity. Users can import directly from a shared
file or paste from the clipboard.
