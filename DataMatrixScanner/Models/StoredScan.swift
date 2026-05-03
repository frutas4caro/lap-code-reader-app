import Foundation
import SwiftData

/// Persistent record of a scan.
///
/// Cells are NOT stored — they're derived on view by re-running the
/// validator and grid inference over `rawPayloads`. `validatorRegexAtCapture`
/// is immutable and used for audit recovery.
@Model
public final class StoredScan {
    /// Stable identifier matching the original `ScanResult.id`.
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    /// Path under `Application Support/Scans/<uuid>/`. `nil` after trim.
    public var sourceImagePath: String?
    /// Path to the initial annotated bake. `nil` before bake or after trim.
    public var annotatedImagePath: String?
    /// Raw decoded payloads at capture time. Cells are derived from these.
    @Relationship(deleteRule: .cascade) public var rawPayloads: [StoredRawPayload]
    /// User edits layered on top of derived cells.
    @Relationship(deleteRule: .cascade) public var edits: [StoredEdit]
    /// Layout selection in storage form (e.g. `"auto"` or `"9x9"`).
    public var layoutMode: String
    /// Validator regex at the moment of capture. Immutable.
    public var validatorRegexAtCapture: String
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceImagePath: String? = nil,
        annotatedImagePath: String? = nil,
        rawPayloads: [StoredRawPayload] = [],
        edits: [StoredEdit] = [],
        layoutMode: String,
        validatorRegexAtCapture: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceImagePath = sourceImagePath
        self.annotatedImagePath = annotatedImagePath
        self.rawPayloads = rawPayloads
        self.edits = edits
        self.layoutMode = layoutMode
        self.validatorRegexAtCapture = validatorRegexAtCapture
        self.isPinned = isPinned
    }
}

/// A single raw decoded payload as captured at scan time. Stored
/// instead of cells so regex changes propagate to history.
@Model
public final class StoredRawPayload {
    @Attribute(.unique) public var id: UUID
    /// Decoded payload string. `nil` for decode-failed bounding boxes.
    public var payload: String?
    /// Normalised UIKit-space bounding box, encoded as four doubles.
    public var bboxX: Double
    public var bboxY: Double
    public var bboxWidth: Double
    public var bboxHeight: Double
    /// Decoder confidence in `0...1`.
    public var confidence: Float
    /// Raw decoded bytes when produced by ZXing fallback.
    public var rawBytes: Data?

    public init(
        id: UUID = UUID(),
        payload: String?,
        bboxX: Double,
        bboxY: Double,
        bboxWidth: Double,
        bboxHeight: Double,
        confidence: Float,
        rawBytes: Data? = nil
    ) {
        self.id = id
        self.payload = payload
        self.bboxX = bboxX
        self.bboxY = bboxY
        self.bboxWidth = bboxWidth
        self.bboxHeight = bboxHeight
        self.confidence = confidence
        self.rawBytes = rawBytes
    }
}

/// A user edit layered on top of derived cells.
///
/// The `kind` discriminator covers all four edit shapes:
/// override a decoded payload, manually populate an empty cell,
/// resolve an unplaced detection, or discard an unplaced detection.
@Model
public final class StoredEdit {
    /// Discriminator for the kind of edit. Stored as a raw string so
    /// the SwiftData schema doesn't require a custom value transformer.
    public enum Kind: String, Codable, Sendable {
        case userOverride
        case userAdded
        case unplacedAction
        case unplacedDiscard
    }

    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    /// Target row. `-1` when the edit refers to an unplaced detection.
    public var row: Int
    /// Target column. `-1` when the edit refers to an unplaced detection.
    public var col: Int
    /// New payload value for `userOverride` / `userAdded` /
    /// `unplacedAction(.edited)`. `nil` for discard.
    public var newPayload: String?
    /// Reference back to an unplaced detection when `kind` is
    /// `unplacedAction` or `unplacedDiscard`.
    public var unplacedID: UUID?

    public var kind: Kind {
        Kind(rawValue: kindRaw) ?? .userOverride
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        row: Int,
        col: Int,
        newPayload: String? = nil,
        unplacedID: UUID? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.row = row
        self.col = col
        self.newPayload = newPayload
        self.unplacedID = unplacedID
    }
}
