import Foundation
import UIKit

/// The full output of a scan, threaded through the UI.
///
/// `cells` and `unplaced` are produced by `GridInferencer`; `csv` is
/// recomputed whenever cells change. `annotatedImage` is `nil` until
/// the pipeline emits its initial bake (live overlay handles the
/// pre-bake window).
public struct ScanResult: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let sourceImage: UIImage
    public var annotatedImage: UIImage?
    public var cells: [GridCell]
    public var unplaced: [UnplacedDetection]
    public var csv: String
    public let layoutMode: BoxLayout
    /// Validator regex captured at scan time. Used for audit recovery.
    public let validatorRegex: String
    public let quality: ScanQualityReport

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceImage: UIImage,
        annotatedImage: UIImage? = nil,
        cells: [GridCell],
        unplaced: [UnplacedDetection] = [],
        csv: String,
        layoutMode: BoxLayout,
        validatorRegex: String,
        quality: ScanQualityReport
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceImage = sourceImage
        self.annotatedImage = annotatedImage
        self.cells = cells
        self.unplaced = unplaced
        self.csv = csv
        self.layoutMode = layoutMode
        self.validatorRegex = validatorRegex
        self.quality = quality
    }
}

/// Errors that abort the pipeline. Note: zero codes is NOT an error —
/// it produces a valid `ScanResult` with all cells `.empty` (in
/// `.fixed` layout) or an empty cells array (in `.auto`).
public enum ScanError: Error, Sendable {
    case permissionDenied
    case imageTooLarge
    case decodeFailed(underlying: Error)
}
