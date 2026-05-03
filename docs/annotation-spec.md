# Annotated Image Specification

## Output
UIImage at same resolution as input (no downscaling).
Rendered via Core Graphics on a GPU-backed CIContext for performance.

## Per-Cell Overlay (color matrix)
Driven by `CellStatus`:

| CellStatus | Stroke color | Label |
|---|---|---|
| `.decoded(code)` (no user override) | green `#00FF88` | payload, e.g. `A00011` |
| `.decoded(code)` with `userOverride` set | blue `#3B82F6` | overridden value |
| `.unreadable(.validatorRejected(p))` | orange `#FF8C00` | `rejected: <p>` |
| `.unreadable(.decodeFailed)` | orange `#FF8C00` | `unreadable` |
| `.unreadable(.lowConfidence(p, _))` | orange `#FF8C00` | `low conf: <p>` |
| `.empty` (fixed layout) | yellow `#FFCC00` dashed | (no label) |
| Outlier (row=-1, col=-1) | yellow `#FFCC00` solid | payload + `outlier` |
| User-added cell (`userAdded == true`) | blue `#3B82F6` | manual value |

- Bounding box: rounded rectangle stroke, 3pt line weight
- Label: rendered above the bounding box
  - Font: SF Mono Bold, size scaled to bounding box width (min 10pt, max 24pt)
  - Background: semi-transparent black pill (#000000 at 65% opacity)
  - Text color: white

## Grid Overlay
- Draw faint grid lines connecting ideal-position centroids of the inferred
  (or declared) row and column axes
  - Color: white at 30% opacity
  - Line weight: 1pt
- Empty cells in `.fixed` layout: dashed yellow rectangle at the ideal position

## Row/Column Labels
- Along the inferred row axis: small row numbers (R1, R2…) at left edge
- Along the inferred column axis: column numbers (C1, C2…) at top edge
- Font: SF Mono, 12pt, white on dark pill background

## Performance Requirement
Annotation of a 100-code image must complete in <2s on iPhone 12 or newer.
