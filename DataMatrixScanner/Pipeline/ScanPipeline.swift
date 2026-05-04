import Foundation
import UIKit

/// Orchestrates the scan pipeline: quality analysis → decode → validate →
/// grid inference → annotation → export → save. Emits `PipelineEvent`s as
/// an `AsyncStream` so the UI can render the grid (`.partial`) before the
/// annotated image bake completes.
///
/// This file is the **scaffold** for the pipeline. Downstream services
/// will plug in at the `// TODO:` points below as separate beads land.
/// The current implementation emits the ordered stage / partial /
/// complete event sequence with an empty-but-well-formed `ScanResult`,
/// so views and tests can integrate against the streaming contract
/// today.
///
/// Sendability note: `UIImage` is not `Sendable`. The scaffold wraps the
/// input image in a local `@unchecked Sendable` envelope (`ImageBox`)
/// to cross the actor boundary. Bead **dms-5c3.4** (BarcodeScanner)
/// will refactor the public API to accept a `CGImage`, which IS
/// `Sendable`, and this envelope will go away.
public actor ScanPipeline {
    /// Creates a new pipeline. Stateless today; will gain injected
    /// services as downstream beads (dms-5c3.4, dms-uff.2, dms-uff.3,
    /// dms-d6u.1, dms-1ni.1, dms-1ni.5) land.
    public init() {}

    /// Runs the pipeline against `image` and emits an ordered stream of
    /// `PipelineEvent`s. The stream finishes after `.complete` (success)
    /// or `.failed` (terminal error). On the happy path it never emits
    /// `.failed` — even zero detections produce a valid `ScanResult`.
    ///
    /// - Parameters:
    ///   - image: Source photo. Captured into a `Sendable` envelope for
    ///     actor crossing; see file-level note about dms-5c3.4.
    ///   - layout: `.auto` or `.fixed(rows, cols)`. In `.fixed` mode the
    ///     scaffold emits `rows * cols` `.empty` cells so the UI has a
    ///     stable grid shape to render against.
    ///   - validatorPattern: Regex captured into the emitted
    ///     `ScanResult.validatorRegex` for audit recovery.
    /// - Returns: An `AsyncStream<PipelineEvent>` consumable from any
    ///   isolation, including `@MainActor`.
    public func run(
        image: UIImage,
        layout: BoxLayout,
        validatorPattern: String
    ) -> AsyncStream<PipelineEvent> {
        let imageBox = ImageBox(image: image)
        return AsyncStream { continuation in
            let task = Task {
                // TODO(dms-5c3.4): replace with real ImageQualityAnalyzer.
                continuation.yield(.stage(.analyzingQuality))

                // TODO(dms-5c3.4): BarcodeScanner (Vision + ZXing) yields
                // `[RawObservation]` here.
                continuation.yield(.stage(.decoding))

                // TODO(dms-5c3.4 / PayloadValidator): partition decoded
                // vs. validator-rejected observations using
                // `validatorPattern`.
                continuation.yield(.stage(.validating))

                // TODO(dms-uff.2 / dms-uff.3): GridInferencer.infer(...)
                // produces `[GridCell]` and `[UnplacedDetection]`.
                continuation.yield(.stage(.inferringGrid))

                let cells = Self.scaffoldCells(for: layout)
                let quality = Self.scaffoldQuality(for: layout)
                let partial = ScanResult(
                    sourceImage: imageBox.image,
                    annotatedImage: nil,
                    cells: cells,
                    unplaced: [],
                    csv: "",
                    layoutMode: layout,
                    validatorRegex: validatorPattern,
                    quality: quality
                )
                continuation.yield(.partial(partial))

                // TODO(dms-d6u.1): ImageAnnotator renders the annotated
                // UIImage and yields `.annotated(_)` here.
                continuation.yield(.stage(.annotating))

                // TODO(dms-1ni.1): CSVExporter computes the CSV string.
                continuation.yield(.stage(.exporting))

                // TODO(dms-1ni.5): StorageManager persists `StoredScan`
                // and writes photo files under Application Support.
                continuation.yield(.stage(.saving))

                continuation.yield(.complete(partial))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Scaffold helpers

    /// Builds the scaffold cell list. `.auto` returns `[]`; `.fixed`
    /// returns a fully-empty `rows * cols` grid in row-major order.
    private static func scaffoldCells(for layout: BoxLayout) -> [GridCell] {
        switch layout {
        case .auto:
            return []
        case let .fixed(rows, cols):
            var cells: [GridCell] = []
            cells.reserveCapacity(rows * cols)
            for row in 1...rows {
                for col in 1...cols {
                    cells.append(GridCell(row: row, col: col, status: .empty))
                }
            }
            return cells
        }
    }

    /// Builds an empty quality report appropriate for the layout.
    private static func scaffoldQuality(for layout: BoxLayout) -> ScanQualityReport {
        let expected: Int?
        switch layout {
        case .auto:
            expected = nil
        case let .fixed(rows, cols):
            expected = rows * cols
        }
        return ScanQualityReport(
            decodedCount: 0,
            rejectedByValidatorCount: 0,
            expectedCount: expected,
            outlierCount: 0,
            principalAxisAngle: 0,
            confidenceFloor: 0,
            warnings: []
        )
    }
}

/// `Sendable` envelope around `UIImage` for the scaffold pipeline.
///
/// `UIImage` is reference-typed and not formally `Sendable`. The
/// scaffold treats the input as immutable for the duration of the run
/// — no mutation, no draw-into. Bead **dms-5c3.4** will replace this
/// with a `CGImage` parameter (which IS `Sendable`) at the public API.
private struct ImageBox: @unchecked Sendable {
    let image: UIImage
}
