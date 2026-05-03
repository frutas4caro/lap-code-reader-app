import CoreGraphics
import Foundation

/// Reason a cell could not be presented as a successfully decoded payload.
public enum UnreadableReason: Hashable, Codable, Sendable {
    /// Decode succeeded but the payload failed the active validator regex.
    case validatorRejected(decodedPayload: String)
    /// A barcode region was detected but no payload could be extracted.
    case decodeFailed
    /// A payload was extracted but the decoder confidence is below the floor.
    case lowConfidence(payload: String, confidence: Float)
}

/// The current display state of a single grid cell.
///
/// Cells are derived from raw payloads + the active validator regex on
/// every render — never persisted directly (see `StoredScan`).
public enum CellStatus: Hashable, Codable, Sendable {
    /// Decoded successfully and accepted by the validator.
    case decoded(DetectedCode)
    /// A detection exists but cannot be presented as a clean payload.
    case unreadable(reason: UnreadableReason, boundingBox: CGRect?)
    /// A declared `.fixed` layout position with no detection.
    case empty
}
