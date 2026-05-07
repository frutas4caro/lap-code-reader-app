import CoreGraphics
import Foundation

/// Conversion of a `ScanResult` into the row/edit shape stored by SwiftData.
///
/// Lives in its own file to keep `StorageManager` focused on the
/// persistence + filesystem lifecycle while the projection logic
/// (cells/unplaced → `StoredRawPayload` and `StoredEdit`) sits next
/// to its own tests-of-record.
extension StorageManager {

    /// Builds `StoredRawPayload`s from the cells/unplaced detections of a
    /// `ScanResult`.
    ///
    /// Spec interpretation: `StoredRawPayload` represents the raw output
    /// of the decoder before validation, so we emit one entry per source
    /// of decoder output:
    ///
    /// - `.decoded(code)` cells — payload + bbox + confidence + rawBytes.
    /// - `.unreadable(.validatorRejected(p), bbox)` cells — payload `p`
    ///   (the decoder DID produce a string; the validator rejected it).
    /// - `.unreadable(.lowConfidence(p, c), bbox)` cells — payload `p`,
    ///   confidence `c`.
    /// - `.unreadable(.decodeFailed, bbox)` cells — `payload = nil`,
    ///   confidence 0 (decode region detected, no string extracted).
    /// - `.empty` cells — produce nothing (no detection occurred).
    /// - Unplaced detections — re-emitted with bbox; placement is
    ///   re-derived on view via `GridInferencer`.
    func rawPayloads(from result: ScanResult) -> [StoredRawPayload] {
        var out: [StoredRawPayload] = []
        for cell in result.cells {
            switch cell.status {
            case let .decoded(code):
                out.append(.from(code: code))
            case let .unreadable(reason, bbox):
                guard let bbox else { continue }
                out.append(payload(for: reason, bbox: bbox))
            case .empty:
                continue
            }
        }
        for unplaced in result.unplaced {
            out.append(.from(
                payload: unplaced.payload,
                bbox: unplaced.boundingBox,
                confidence: unplaced.confidence,
                rawBytes: unplaced.rawBytes
            ))
        }
        return out
    }

    /// Builds `StoredEdit`s from the user-side state on `ScanResult`:
    /// per-cell `userOverride`, `userAdded` flags, and any non-`.none`
    /// `UnplacedAction`s.
    func edits(from result: ScanResult) -> [StoredEdit] {
        var out: [StoredEdit] = []
        for cell in result.cells {
            if cell.userAdded {
                out.append(StoredEdit(
                    kind: .userAdded,
                    row: cell.row,
                    col: cell.col,
                    newPayload: cell.userOverride
                ))
            } else if let override = cell.userOverride {
                out.append(StoredEdit(
                    kind: .userOverride,
                    row: cell.row,
                    col: cell.col,
                    newPayload: override
                ))
            }
        }
        for unplaced in result.unplaced {
            if let edit = unplacedEdit(for: unplaced) {
                out.append(edit)
            }
        }
        return out
    }

    // MARK: - Helpers

    private func payload(
        for reason: UnreadableReason,
        bbox: CGRect
    ) -> StoredRawPayload {
        switch reason {
        case let .validatorRejected(decodedPayload):
            return .from(payload: decodedPayload, bbox: bbox, confidence: 0, rawBytes: nil)
        case let .lowConfidence(payload, confidence):
            return .from(payload: payload, bbox: bbox, confidence: confidence, rawBytes: nil)
        case .decodeFailed:
            return .from(payload: nil, bbox: bbox, confidence: 0, rawBytes: nil)
        }
    }

    private func unplacedEdit(for unplaced: UnplacedDetection) -> StoredEdit? {
        switch unplaced.action {
        case .none, .keptAsOutlier:
            return nil
        case let .placed(row, col):
            return StoredEdit(
                kind: .unplacedAction,
                row: row,
                col: col,
                newPayload: unplaced.payload,
                unplacedID: unplaced.id
            )
        case let .edited(newPayload):
            return StoredEdit(
                kind: .unplacedAction,
                row: -1,
                col: -1,
                newPayload: newPayload,
                unplacedID: unplaced.id
            )
        case .discarded:
            return StoredEdit(
                kind: .unplacedDiscard,
                row: -1,
                col: -1,
                newPayload: nil,
                unplacedID: unplaced.id
            )
        }
    }
}

// MARK: - StoredRawPayload init helpers

extension StoredRawPayload {
    static func from(code: DetectedCode) -> StoredRawPayload {
        StoredRawPayload(
            payload: code.payload,
            bboxX: Double(code.boundingBox.origin.x),
            bboxY: Double(code.boundingBox.origin.y),
            bboxWidth: Double(code.boundingBox.size.width),
            bboxHeight: Double(code.boundingBox.size.height),
            confidence: code.confidence,
            rawBytes: code.rawBytes
        )
    }

    static func from(
        payload: String?,
        bbox: CGRect,
        confidence: Float,
        rawBytes: Data?
    ) -> StoredRawPayload {
        StoredRawPayload(
            payload: payload,
            bboxX: Double(bbox.origin.x),
            bboxY: Double(bbox.origin.y),
            bboxWidth: Double(bbox.size.width),
            bboxHeight: Double(bbox.size.height),
            confidence: confidence,
            rawBytes: rawBytes
        )
    }
}
