## ADDED Requirements

### Requirement: SwiftData StoredScan with file-backed photos

The system SHALL persist scans using SwiftData with the following schema:

```swift
@Model class StoredScan {
    var id: UUID
    var timestamp: Date
    var sourceImagePath: String         // Application Support/Scans/<uuid>/input.jpg
    var annotatedImagePath: String?     // nil after photo trim or pre-bake
    var rawPayloads: [StoredRawPayload] // payload, bbox, confidence, rawBytes
    var edits: [StoredEdit]             // userOverride per (row, col), userAdded, discarded
    var layoutMode: String              // "auto" | "9x9" etc.
    var validatorRegexAtCapture: String // immutable
    var isPinned: Bool
}
```

Photo bytes SHALL live on disk under `Application Support/Scans/<uuid>/`. SwiftData SHALL store paths only.

#### Scenario: Saving a scan writes photo files and SwiftData record

- **WHEN** the pipeline auto-persists a scan
- **THEN** `Application Support/Scans/<uuid>/input.jpg` exists
- **AND** a `StoredScan` row exists with `sourceImagePath` pointing to that file

### Requirement: Cells are derived, not stored

The system SHALL NOT persist `[GridCell]` directly. Cell statuses SHALL be computed on view by:
1. Loading `rawPayloads` from `StoredScan`
2. Applying the *current* `validatorRegex` from `@AppStorage`
3. Re-running grid inference using the stored `layoutMode`
4. Layering `edits` on top (userOverride, userAdded, discarded)

The result SHALL match what the user saw at the original scan time when `validatorRegex == validatorRegexAtCapture` AND `gapThresholdMultiplier` / `outlierSigmaThreshold` are unchanged.

#### Scenario: Regex change changes derived cells without mutating storage

- **GIVEN** a saved scan with `validatorRegexAtCapture = "^[A-Z]\d{5}$"` containing payload `"AB1234"` (rejected at capture)
- **WHEN** the user changes the regex in Settings to `"^[A-Z]{2}\d{4}$"` and reopens the scan
- **THEN** the displayed cell containing `"AB1234"` shows as `decoded`
- **AND** `StoredScan.validatorRegexAtCapture` is unchanged

### Requirement: Auto-trim retention

The system SHALL run an auto-trim pass on app launch and after each scan saves. Photo files SHALL be deleted when:
- The scan's `timestamp` is older than `retentionDays` (default 30) **OR**
- Total `Application Support/Scans/` size exceeds `maxStorageBytes` (default 1 GB; trim oldest first until under cap)

The corresponding `StoredScan` record SHALL be retained as lightweight history; `sourceImagePath` and `annotatedImagePath` SHALL be set to nil.

#### Scenario: 31-day-old scan loses its photo, keeps its record

- **GIVEN** a scan with `timestamp` 31 days ago and `retentionDays = 30`
- **WHEN** the auto-trim pass runs
- **THEN** the photo files are deleted from disk
- **AND** the `StoredScan` record still exists with `sourceImagePath = nil` and `annotatedImagePath = nil`

#### Scenario: Storage cap exceeded trims oldest first

- **GIVEN** total scan storage is 1.2 GB and `maxStorageBytes = 1_073_741_824` (1 GB)
- **WHEN** the auto-trim pass runs
- **THEN** the oldest scans' photo files are deleted until total storage is below 1 GB
- **AND** records for trimmed scans remain

### Requirement: Trimmed scans render gracefully

The system SHALL render `HistoryView` entries for scans whose photo files have been trimmed with a placeholder thumbnail and the label "(images cleared)". The user SHALL still be able to view the derived cells, CSV, and metadata for trimmed scans.

#### Scenario: Viewing a trimmed scan

- **WHEN** the user taps a `StoredScan` row whose `sourceImagePath` is nil
- **THEN** `ResultView` displays the cells and CSV
- **AND** the image area shows "(images cleared)" with a placeholder
- **AND** annotation bake and "Export Test Case" actions are disabled
