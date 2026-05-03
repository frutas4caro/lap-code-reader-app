## ADDED Requirements

### Requirement: Pipeline emits AsyncStream of events

The system SHALL provide a `ScanPipeline` actor with `run(image: UIImage, layout: BoxLayout, validator: PayloadValidator) -> AsyncStream<PipelineEvent>`. Events SHALL be emitted in this order on success: `.stage(...)` (multiple, one per stage), `.partial(ScanResult)`, `.annotated(UIImage)`, `.complete(ScanResult)`. Events SHALL be emitted on a background actor; consumers on `@MainActor` SHALL hop the stream.

#### Scenario: Successful run emits expected event sequence

- **WHEN** `pipeline.run(image:, layout: .fixed(9,9), validator:)` is called for a normal photo
- **THEN** the stream emits at least one `.partial(ScanResult)` before `.complete(ScanResult)`
- **AND** the stream emits exactly one `.annotated(UIImage)` before `.complete(...)`
- **AND** the stream terminates after `.complete(...)`

### Requirement: Best-effort, never-abort

The system SHALL produce a valid `ScanResult` even when input quality is poor or zero codes are detected. Only the following conditions SHALL emit `PipelineEvent.failed(ScanError)` and terminate the stream:
- `ScanError.permissionDenied` (camera/photo permission missing)
- `ScanError.imageTooLarge` (input exceeds memory budget)
- `ScanError.decodeFailed(underlying:)` (CGImage extraction failed or system error)

Decode misses, low confidence, validator rejection, grid inference fallback to defaults, and zero detections SHALL NOT cause failure — they SHALL produce a `ScanResult` with appropriate `unreadable` / `empty` cells and a populated `ScanQualityReport`.

#### Scenario: Zero detections produces empty fixed-grid result

- **WHEN** the input image contains no decodable codes and layout is `.fixed(9, 9)`
- **THEN** the stream emits `.partial` and `.complete` with 81 cells, all `status = .empty`
- **AND** no `.failed(...)` event is emitted

#### Scenario: Permission denied terminates with failed event

- **WHEN** the user has denied camera permission and the pipeline is invoked from camera capture
- **THEN** the stream emits `.failed(.permissionDenied)` as its terminal event
- **AND** no `.partial`, `.annotated`, or `.complete` events are emitted

### Requirement: Partial result enables editing before annotation completes

The system SHALL emit `.partial(ScanResult)` as soon as decode + validate + grid-inference complete, before annotation rendering begins. The partial `ScanResult` SHALL have `cells` populated and `annotatedImage = nil`. The user SHALL be able to edit cells against the partial result.

#### Scenario: User edits a cell during annotation

- **WHEN** `.partial` has been emitted but `.annotated` has not
- **AND** the user opens the cell editor and changes a payload
- **THEN** the edit is applied to the working `ScanResult`
- **AND** the subsequent `.annotated(UIImage)` event does NOT overwrite the user's edit

### Requirement: Pipeline stages

The system SHALL emit `.stage(PipelineStage)` events with at least these stages, in order: `.analyzingQuality`, `.decoding`, `.validating`, `.inferringGrid`, `.annotating`, `.exporting`, `.saving`. Stages are progress labels for the UI; their exact timing is not specified.

#### Scenario: UI shows progress labels

- **WHEN** the pipeline is running
- **THEN** the stream emits at least one `.stage(...)` event for each pipeline phase
- **AND** stages are emitted in the order listed above (some may be emitted multiple times for retry paths)

### Requirement: Performance budgets

The system SHALL bake the annotated image for a 100-code input in under 2 seconds on iPhone 12 hardware. The system SHALL complete the full pipeline (run start → `.complete`) for a 100-code input in under 3 seconds on iPhone 12 hardware. The `.partial` emit latency budget is intentionally unspecified pending benchmark data.

#### Scenario: 100-code annotation bake under 2s

- **WHEN** running on iPhone 12 with a 100-code 12MP input
- **THEN** the time from start to `.annotated(...)` event is < 2.0 seconds

#### Scenario: 100-code end-to-end under 3s

- **WHEN** running on iPhone 12 with a 100-code 12MP input
- **THEN** the time from start to `.complete(...)` event is < 3.0 seconds
