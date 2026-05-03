# Grid Inference Algorithm

## Problem
Up to 100 Data Matrix codes are arranged in a grid that:
- May be rotated at any angle relative to the photo
- May have missing cells (empty positions in the grid)
- Is NOT guaranteed to be axis-aligned
- May be **sparse** (e.g. 6 vials in a 9×9 box) — pure inference would
  report a 2×3 grid, hiding the missing positions

## Layout Modes

```swift
enum BoxLayout {
    case auto                                       // infer everything from centroids
    case fixed(rows: Int, cols: Int)                // user-declared box dimensions
}

func infer(codes: [DetectedCode], layout: BoxLayout) -> [GridCell]
```

The CEL default is `.fixed(9, 9)`; the public default is `.auto`. The user
can override per-scan from `ScanView` without touching Settings.

## Auto Mode

### Step 1 — Find principal axis
Compute centroids of all DetectedCodes. Run PCA on the centroid point cloud
to find the two principal axes. The dominant axis is the grid's row direction;
the orthogonal axis is the column direction. This handles arbitrary rotation.

### Step 2 — Project onto axes
Project each centroid onto both axes to get a 1D coordinate along each.

### Step 3 — Cluster into rows and columns
Run 1D gap clustering on each axis projection independently.
- Sort projections
- Compute gaps between consecutive values
- Gaps significantly larger than median inter-code spacing indicate a new
  row (or column)
- Default gap threshold = 1.5× median spacing (Settings: `gapThresholdMultiplier`)

### Step 4 — Assign row/col indices
After clustering, assign 1-based row and column indices sorted by projection
value (low projection = row 1 / col 1).

### Step 5 — Build [GridCell]
Build a full row × col grid. Any (row, col) combination with no detected code
becomes `GridCell(status: .empty)`. Detected codes become
`GridCell(status: .decoded(...))`.

## Fixed Mode

### Step 1 — PCA for orientation only
Same PCA step as Auto, but the row/col counts are **forced** to the user's
declared `(rows, cols)`. PCA is used solely to recover the grid's rotation
relative to the photo.

### Step 2 — Construct ideal grid
Place `rows × cols` ideal positions by extending along the principal axes,
spaced by the median inter-centroid distance, anchored at the centroid of
all detections.

### Step 3 — Map detections to ideal positions
For each detected centroid, find the nearest ideal position. If the distance
is within `outlierSigmaThreshold × σ` of the median spacing, assign it.

### Step 4 — Fill remaining ideal positions with `.empty`
Any ideal position with no assigned detection becomes
`GridCell(status: .empty)`.

### Step 5 — Outliers
Detections that did NOT map to any ideal position (distance > threshold)
become outlier cells: `GridCell(row: -1, col: -1, status: .decoded(...))`.
They render in the CSV as `row=null, col=null` and in the annotated image
with a yellow border. **They are never silently dropped.**

## Validator-Rejected Codes
Decoded codes whose payload did not match the validator regex are passed
into `infer(...)` as `RawObservation`s with their bbox, then placed by the
same nearest-ideal-position logic. They become
`GridCell(status: .unreadable(reason: .validatorRejected(decodedPayload: ...)))`.

## Edge Cases
- Single row or single column (auto only): PCA degenerates. Fall back to 1D
  clustering on the non-degenerate axis.
- Fewer than 3 codes (auto only): skip PCA, assign codes sequentially.
- Zero codes detected: in `.fixed` mode, return `rows × cols` empty cells.
  In `.auto` mode, return `[]`. Either way, the pipeline produces a valid
  `ScanResult` and the user lands on `ResultView` with recommendations.

## Tunable Parameters (Settings)
- `gapThresholdMultiplier: Float = 1.5`
- `outlierSigmaThreshold: Float = 3.0`
