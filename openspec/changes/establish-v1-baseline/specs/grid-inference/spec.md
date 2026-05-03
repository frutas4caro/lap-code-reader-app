## ADDED Requirements

### Requirement: Two layout modes — auto and fixed

The system SHALL support two layout modes selected per-scan via `BoxLayout`:
- `.auto`: row and column counts inferred from the centroid distribution.
- `.fixed(rows: Int, cols: Int)`: caller declares the grid dimensions; PCA is used only to recover orientation.

The CEL default SHALL be `.fixed(9, 9)`; the public default SHALL be `.auto`. Both defaults SHALL be overridable per-scan from `ScanView`.

#### Scenario: Fixed mode produces exactly rows×cols cells

- **WHEN** `infer(codes: [...], layout: .fixed(rows: 9, cols: 9))` is called with 46 detections
- **THEN** the result contains exactly 81 cells
- **AND** the 35 cells with no nearby detection have `status = .empty`

#### Scenario: Auto mode infers grid dimensions from data

- **WHEN** `infer(codes: [...], layout: .auto)` is called with detections forming a 3-row × 4-column pattern
- **THEN** the result contains 12 cells with `row ∈ 1...3` and `col ∈ 1...4`

### Requirement: PCA-based orientation recovery

The system SHALL compute the principal axes of the centroid point cloud via PCA. The dominant axis SHALL be treated as the row direction; the orthogonal axis as the column direction. This SHALL apply to both layout modes, allowing the grid to be rotated at any angle relative to the photo.

#### Scenario: Grid rotated 30° decodes to upright row/col indices

- **WHEN** detections are arranged in a 5×5 grid rotated 30° in the photo
- **THEN** the inferred cells have row/col indices identical to a non-rotated 5×5 input
- **AND** the `ScanQualityReport.principalAxisAngle` is approximately 30°

### Requirement: Fewer than 3 codes in auto mode

The system SHALL skip PCA when `codes.count < 3` in auto mode and assign codes sequentially as a single row.

#### Scenario: Two codes produce a 1×2 grid

- **WHEN** `infer(codes: [c1, c2], layout: .auto)` is called
- **THEN** the result is `[GridCell(row: 1, col: 1), GridCell(row: 1, col: 2)]` ordered by horizontal position

### Requirement: Unplaced detections (outliers and rejected)

The system SHALL produce an `unplaced: [UnplacedDetection]` list alongside `[GridCell]`. An `UnplacedDetection` represents a detection that could not be confidently mapped to a grid cell, including:
- Spatial outliers in `.fixed` mode (distance to nearest ideal position > `outlierSigmaThreshold × σ`).
- Validator-rejected detections whose nearest ideal position is also beyond the outlier threshold.
- Decode-failed bounding boxes (Vision saw a region but extracted no payload).

Unplaced detections SHALL NEVER be silently dropped.

#### Scenario: Outlier in fixed mode appears in unplaced list

- **WHEN** a 9×9 fixed-mode scan has one detection 4σ from any ideal position
- **THEN** the result has 81 grid cells (with that position marked `.empty`)
- **AND** the `unplaced` list contains one entry with the outlier's payload, bbox, and reason `.spatialOutlier`

#### Scenario: Decode-failed bbox appears in unplaced list

- **WHEN** Vision detects a barcode region but cannot extract a payload (and ZXing fallback also fails)
- **THEN** the unplaced list contains an entry with `payload = nil`, `boundingBox` populated, and reason `.decodeFailed`

### Requirement: Validator-rejected codes that map to a grid position

The system SHALL place validator-rejected detections at their nearest ideal position when within the outlier threshold. The resulting cell SHALL have `status = .unreadable(.validatorRejected(decodedPayload: <payload>))`. Only when the rejected detection is *also* a spatial outlier SHALL it move to the unplaced list.

#### Scenario: Rejected payload near an ideal position

- **WHEN** a 9×9 fixed-mode scan has a detection at row=2, col=3 with payload `"AOO011"` (validator-rejected, spatially within threshold)
- **THEN** the cell at (2, 3) has `status = .unreadable(.validatorRejected(decodedPayload: "AOO011"))`
- **AND** the unplaced list does not contain this detection

### Requirement: Tunable parameters from settings

The system SHALL read `gapThresholdMultiplier` (default 1.5) and `outlierSigmaThreshold` (default 3.0) from `@AppStorage`. Both SHALL be configurable in Settings.

#### Scenario: Increasing gap threshold collapses adjacent rows

- **GIVEN** a centroid pattern where rows are separated by 1.4× median spacing
- **WHEN** `gapThresholdMultiplier = 1.5`
- **THEN** auto mode infers a single row
- **WHEN** `gapThresholdMultiplier` is changed to `1.3`
- **THEN** auto mode infers two rows
