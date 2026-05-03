import CoreGraphics
import Foundation

/// Why a detection ended up in the unplaced strip rather than a grid cell.
public enum UnplacedReason: Hashable, Codable, Sendable {
    /// `.fixed` mode: nearest ideal position is beyond the outlier threshold.
    case spatialOutlier
    /// Vision detected a barcode region but no payload could be extracted.
    case decodeFailed
    /// Validator-rejected detection that is also a spatial outlier.
    case validatorRejectedOutlier(decodedPayload: String)
}

/// User action recorded for an unplaced detection at edit time.
///
/// `.none` means the user has not yet acted on the entry.
public enum UnplacedAction: Hashable, Codable, Sendable {
    case none
    case placed(row: Int, col: Int)
    case edited(newPayload: String)
    case keptAsOutlier
    case discarded
}

/// A detection that could not be confidently mapped into the grid.
///
/// Audit guarantee: unplaced detections are NEVER silently dropped.
/// They surface in the unplaced strip alongside the grid and produce
/// a CSV row even when the user discards them.
public struct UnplacedDetection: Hashable, Codable, Sendable, Identifiable {
    /// Stable identity for SwiftUI lists.
    public let id: UUID
    /// Decoded payload. `nil` when `reason == .decodeFailed`.
    public let payload: String?
    /// Normalised UIKit-space bounding box.
    public let boundingBox: CGRect
    /// Decoder confidence in the range `0...1`.
    public let confidence: Float
    /// Why this detection was unplaced.
    public let reason: UnplacedReason
    /// Raw decoded bytes when produced by the ZXing fallback.
    public let rawBytes: Data?
    /// Action recorded by the user during editing.
    public var action: UnplacedAction

    /// Creates an unplaced detection.
    public init(
        id: UUID = UUID(),
        payload: String?,
        boundingBox: CGRect,
        confidence: Float,
        reason: UnplacedReason,
        rawBytes: Data? = nil,
        action: UnplacedAction = .none
    ) {
        self.id = id
        self.payload = payload
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.reason = reason
        self.rawBytes = rawBytes
        self.action = action
    }
}
