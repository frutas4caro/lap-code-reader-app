import CoreGraphics
import Foundation
import os
import UIKit

/// Orchestrates the scan pipeline: quality analysis → decode → validate →
/// grid inference → annotation → export → save. Emits `PipelineEvent`s as
/// an `AsyncStream` so the UI can render the grid (`.partial`) before the
/// annotated image bake completes.
///
/// v1.0 wiring:
/// - `ImageQualityAnalyzer` is intentionally skipped; `analyzingQuality`
///   stage is emitted for telemetry only and an empty-but-valid
///   `ScanQualityReport` is produced. Real warning assembly lands with
///   `dms-uff`.
/// - When a `StorageManager` is injected (v1.1+), the `.saving` stage
///   triggers `StorageManager.save(_:)`. Save failures are logged via
///   `os.Logger` and SWALLOWED — the pipeline still emits `.complete`
///   so transient persistence errors never block the user. When no
///   manager is injected (the v1.0 default and the unit-test default),
///   `.saving` is emitted as a no-op label, preserving prior behaviour.
///
/// Sendability: the public API takes a `CGImage` (which IS `Sendable`),
/// so no `@unchecked Sendable` wrapper is required to cross the actor
/// boundary. The source `UIImage` consumed by the rest of the pipeline
/// is reconstructed via `UIImage(cgImage:)` inside the actor.
public actor ScanPipeline {

    private let scanner: BarcodeScanner
    private let inferencer: GridInferencer
    private let annotator: ImageAnnotator
    private let csvExporter: CSVExporter
    private let storageManager: StorageManager?

    private static let logger = Logger(
        subsystem: "com.cel.datamatrixscanner",
        category: "ScanPipeline"
    )

    /// Creates a new pipeline. Service dependencies default to standard
    /// implementations; callers may inject alternatives for testing. This
    /// is the seam where future fakes/spies will land — see dms-ay9.
    ///
    /// - Parameter storageManager: Optional persistence sink. When `nil`
    ///   the `.saving` stage is a no-op (used by v1.0 callers and most
    ///   unit tests, which don't need a SwiftData container). When set,
    ///   `.saving` calls `StorageManager.save(_:)`; failures are logged
    ///   and swallowed.
    public init(
        scanner: BarcodeScanner = BarcodeScanner(),
        inferencer: GridInferencer = GridInferencer(),
        annotator: ImageAnnotator = ImageAnnotator(),
        csvExporter: CSVExporter = CSVExporter(),
        storageManager: StorageManager? = nil
    ) {
        self.scanner = scanner
        self.inferencer = inferencer
        self.annotator = annotator
        self.csvExporter = csvExporter
        self.storageManager = storageManager
    }

    /// Runs the pipeline against `cgImage` and emits an ordered stream of
    /// `PipelineEvent`s. The stream finishes after `.complete` (success)
    /// or `.failed` (terminal error). On the happy path it never emits
    /// `.failed` — even zero detections produce a valid `ScanResult`.
    ///
    /// - Parameters:
    ///   - cgImage: Source image. `CGImage` is `Sendable`, so it crosses
    ///     the actor boundary cleanly.
    ///   - layout: `.auto` or `.fixed(rows, cols)`. In `.fixed` mode the
    ///     inferencer always returns `rows × cols` cells.
    ///   - validatorPattern: Regex captured into the emitted
    ///     `ScanResult.validatorRegex` for audit recovery, and used to
    ///     instantiate the per-run `PayloadValidator`.
    /// - Returns: An `AsyncStream<PipelineEvent>` consumable from any
    ///   isolation, including `@MainActor`.
    public func run(
        cgImage: CGImage,
        layout: BoxLayout,
        validatorPattern: String
    ) -> AsyncStream<PipelineEvent> {
        let scanner = self.scanner
        let inferencer = self.inferencer
        let annotator = self.annotator
        let csvExporter = self.csvExporter
        let storageManager = self.storageManager

        return AsyncStream { continuation in
            let task = Task {
                await Self.execute(
                    cgImage: cgImage,
                    layout: layout,
                    validatorPattern: validatorPattern,
                    scanner: scanner,
                    inferencer: inferencer,
                    annotator: annotator,
                    csvExporter: csvExporter,
                    storageManager: storageManager,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // swiftlint:disable function_parameter_count function_body_length
    /// Internal pipeline body. Extracted from `run(...)` so the public
    /// entry point stays under the lint body-length budget.
    private static func execute(
        cgImage: CGImage,
        layout: BoxLayout,
        validatorPattern: String,
        scanner: BarcodeScanner,
        inferencer: GridInferencer,
        annotator: ImageAnnotator,
        csvExporter: CSVExporter,
        storageManager: StorageManager?,
        continuation: AsyncStream<PipelineEvent>.Continuation
    ) async {
        // TODO(dms-uff: ImageQualityAnalyzer) — emit stage label only;
        // quality analysis is deferred to v1.0.x.
        continuation.yield(.stage(.analyzingQuality))

        // Decode.
        continuation.yield(.stage(.decoding))
        let detections: [DetectedCode]
        do {
            detections = try await scanner.scan(cgImage: cgImage)
        } catch let error as ScanError {
            continuation.yield(.failed(error))
            continuation.finish()
            return
        } catch {
            continuation.yield(.failed(.decodeFailed(underlying: error)))
            continuation.finish()
            return
        }

        // Validate. Feed *all* detections (accepted + rejected) into
        // GridInferencer so spatial placement uses the full point
        // cloud, then post-process to demote rejected cells into
        // `.unreadable(.validatorRejected(...))`. This avoids
        // expanding the inferencer's API in v1.0.
        continuation.yield(.stage(.validating))
        let validator = PayloadValidator(pattern: validatorPattern)
        let rejectedPayloads: Set<String> = Set(
            detections
                .filter { !validator.matches($0.payload) }
                .map { $0.payload }
        )

        // Infer grid.
        continuation.yield(.stage(.inferringGrid))
        let inference = inferencer.infer(codes: detections, layout: layout)
        let placedCells = applyValidatorRejection(
            cells: inference.cells,
            rejectedPayloads: rejectedPayloads
        )

        // Build partial ScanResult.
        let sourceImage = UIImage(cgImage: cgImage)
        let csv = csvExporter.export(cells: placedCells)
        let quality = buildQualityReport(
            cells: placedCells,
            rejectedCount: rejectedPayloads.count,
            outlierCount: inference.unplaced.count,
            layout: layout
        )
        var scanResult = ScanResult(
            sourceImage: sourceImage,
            annotatedImage: nil,
            cells: placedCells,
            unplaced: inference.unplaced,
            csv: csv,
            layoutMode: layout,
            validatorRegex: validatorPattern,
            quality: quality
        )
        continuation.yield(.partial(scanResult))

        // Annotate.
        continuation.yield(.stage(.annotating))
        let annotated = annotator.annotate(image: sourceImage, cells: placedCells)
        continuation.yield(.annotated(annotated))
        scanResult.annotatedImage = annotated

        // Export — CSV is already on `scanResult`. Stage label emitted
        // for telemetry symmetry.
        continuation.yield(.stage(.exporting))

        // Persistence (v1.1+). Failures are non-fatal: the user still
        // sees `.complete` even if the SwiftData write or photo write
        // throws. Errors are logged via os.Logger for diagnostics.
        continuation.yield(.stage(.saving))
        if let storage = storageManager {
            do {
                _ = try await storage.save(scanResult)
            } catch {
                logger.warning(
                    "StorageManager.save failed (non-fatal): \(String(describing: error), privacy: .public)"
                )
            }
        }

        continuation.yield(.complete(scanResult))
        continuation.finish()
    }
    // swiftlint:enable function_parameter_count function_body_length

    // MARK: - Helpers

    /// For each `.decoded` cell whose payload is in `rejectedPayloads`,
    /// rewrites the cell into `.unreadable(.validatorRejected(...))`,
    /// preserving the cell's `(row, col)` placement. Cells the inferencer
    /// already marked `.unreadable` or `.empty` are passed through.
    private static func applyValidatorRejection(
        cells: [GridCell],
        rejectedPayloads: Set<String>
    ) -> [GridCell] {
        guard !rejectedPayloads.isEmpty else { return cells }
        return cells.map { cell in
            guard case let .decoded(code) = cell.status,
                  rejectedPayloads.contains(code.payload) else {
                return cell
            }
            return GridCell(
                row: cell.row,
                col: cell.col,
                status: .unreadable(
                    reason: .validatorRejected(decodedPayload: code.payload),
                    boundingBox: code.boundingBox
                ),
                userOverride: cell.userOverride,
                userAdded: cell.userAdded
            )
        }
    }

    /// Builds the v1.0 ScanQualityReport. Warnings are intentionally
    /// empty here — full warning assembly lands with `dms-uff`.
    private static func buildQualityReport(
        cells: [GridCell],
        rejectedCount: Int,
        outlierCount: Int,
        layout: BoxLayout
    ) -> ScanQualityReport {
        let expected: Int?
        switch layout {
        case .auto:
            expected = nil
        case let .fixed(rows, cols):
            expected = rows * cols
        }
        var decodedCount = 0
        var minConfidence: Float = .greatestFiniteMagnitude
        for cell in cells {
            if case let .decoded(code) = cell.status {
                decodedCount += 1
                if code.confidence < minConfidence {
                    minConfidence = code.confidence
                }
            }
        }
        let confidenceFloor: Float = decodedCount > 0 ? minConfidence : 0
        return ScanQualityReport(
            decodedCount: decodedCount,
            rejectedByValidatorCount: rejectedCount,
            expectedCount: expected,
            outlierCount: outlierCount,
            principalAxisAngle: 0,
            confidenceFloor: confidenceFloor,
            warnings: []
        )
    }
}
