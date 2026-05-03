## ADDED Requirements

### Requirement: Live overlay reflects current cells

The system SHALL render a live overlay (SwiftUI `Canvas`) composited over the source `UIImage` in `ResultView`. Overlay content SHALL be derived from the current `cells` and `unplaced` lists at every render pass — there SHALL be no cached UIImage backing the live view. Edits to cells SHALL be reflected in the overlay within one frame of the edit being committed.

#### Scenario: Editing a cell updates overlay immediately

- **WHEN** the user changes a cell's `userOverride` from nil to `"A00012"`
- **THEN** the cell's overlay stroke turns blue (`#3B82F6`) on the next render pass
- **AND** the label text updates to `"A00012"`

#### Scenario: Live overlay works before annotation bake completes

- **WHEN** `.partial(ScanResult)` has been received but `.annotated(...)` has not
- **AND** the user taps a cell in `GridView`
- **THEN** the corresponding bounding box is highlighted in the live overlay

### Requirement: Color matrix for cell status

The system SHALL stroke each cell's overlay according to this matrix:

| Cell condition | Stroke color | Style | Label |
|---|---|---|---|
| `.decoded(code)`, no override | green `#00FF88` | solid | payload |
| `.decoded(code)` with `userOverride` | blue `#3B82F6` | solid | overridden value |
| `.unreadable(.validatorRejected(p))` | orange `#FF8C00` | solid | `rejected: <p>` |
| `.unreadable(.decodeFailed)` | orange `#FF8C00` | solid | `unreadable` |
| `.unreadable(.lowConfidence(p, _))` | orange `#FF8C00` | solid | `low conf: <p>` |
| `.empty` (fixed layout) | yellow `#FFCC00` | dashed | (none) |
| User-added cell (`userAdded == true`) | blue `#3B82F6` | solid | manual value |

#### Scenario: Validator-rejected cell renders orange with rejected label

- **WHEN** a cell has `status = .unreadable(.validatorRejected(decodedPayload: "AOO011"))`
- **THEN** its overlay stroke is orange `#FF8C00`
- **AND** its label reads `"rejected: AOO011"`

### Requirement: Unplaced strip UI

The system SHALL display an "Unplaced" strip alongside the grid in `ResultView` when the `unplaced` list is non-empty. Each item SHALL show a cropped thumbnail of the source image around the detection's bbox, the payload (or `"(no payload)"` for decode-failed), and the reason. Tapping an item SHALL open an editor offering: place at (row, col) via picker, edit payload, keep as outlier, discard.

#### Scenario: Unplaced item placed at a grid position

- **GIVEN** the unplaced list contains one item with payload `"B99999"`
- **WHEN** the user taps the item, picks (row=4, col=5), and confirms
- **THEN** the cell at (4, 5) becomes `decoded` with `userOverride = "B99999"` and `userAdded = true`
- **AND** the unplaced list no longer contains the item

#### Scenario: Unplaced item kept as outlier

- **WHEN** the user chooses "Keep as outlier" for an unplaced item with payload `"X12345"`
- **THEN** the item remains in a `cells` entry with `row = -1, col = -1, status = .decoded(...)`
- **AND** CSV export renders the row with `row=null, col=null, code=X12345`

#### Scenario: Unplaced item discarded

- **WHEN** the user chooses "Discard" for an unplaced item with payload `"Z00000"`
- **THEN** the item moves to a `discarded` list on the working `ScanResult`
- **AND** with provenance ON, CSV export contains a row `null,null,Z00000,discarded`
- **AND** with provenance OFF, CSV export contains a row `null,null,Z00000`

### Requirement: Save state machine

The system SHALL track an explicit save state on the working `ScanResult` with values: `unsaved` (post-pipeline, no edits), `dirty` (any edit since last save), `saving` (write in progress), `saved` (persisted, no pending edits). The pipeline's auto-persist at end-of-pipeline SHALL set state to `unsaved` (the original is saved; no edits exist yet). Each user edit SHALL transition `unsaved | saved → dirty`. Tapping "Save" SHALL transition `dirty → saving → saved` on success.

#### Scenario: First edit transitions to dirty

- **GIVEN** the pipeline has emitted `.complete(...)` and the state is `unsaved`
- **WHEN** the user edits any cell
- **THEN** the save state becomes `dirty`

#### Scenario: TestCaseBundle export gated on saved state

- **WHEN** the user taps "Export Test Case" while save state is `dirty`
- **THEN** the system prompts "Save first?" and does not produce a bundle
- **WHEN** the user taps "Export Test Case" while save state is `saved`
- **THEN** a bundle is produced

### Requirement: Tap-to-highlight cross-link between grid and image

The system SHALL highlight the corresponding bounding box in the live overlay when the user taps a cell in `GridView`, and vice versa. Highlighting SHALL work on partial results (before the initial annotation bake completes).

#### Scenario: Grid tap highlights image bbox

- **WHEN** the user taps the cell at (3, 5) in `GridView`
- **THEN** the live overlay strokes that cell's bounding box with a 5pt highlight ring
- **AND** the overlay scrolls to bring the bbox into view if needed

### Requirement: Recommendation surfaces

The system SHALL display per-cell recommendations (sheet from cell editor) and scan-level recommendations (banner stack at top of `ResultView`) produced by `RemediationAdvisor`. Recommendations with actionable buttons (e.g., "Relax validator", "Retake photo", "Manually enter code") SHALL execute the action when tapped.

#### Scenario: Scan with many validator-rejected codes shows banner

- **WHEN** a scan has ≥3 validator-rejected cells
- **THEN** `ResultView` displays a banner with title "Validator rejected 3 codes" and an action button "Relax validator…"
