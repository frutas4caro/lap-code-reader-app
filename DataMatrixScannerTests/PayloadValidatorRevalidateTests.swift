import CoreGraphics
import XCTest
@testable import DataMatrixScanner

/// Tests for `PayloadValidator.revalidate(rawPayloads:)` — the pure
/// re-validation entry point that powers the derived-cell model.
final class PayloadValidatorRevalidateTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRaw(
        payload: String?,
        confidence: Float = 0.95,
        bbox: CGRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        rawBytes: Data? = nil
    ) -> StoredRawPayload {
        StoredRawPayload(
            payload: payload,
            bboxX: bbox.origin.x,
            bboxY: bbox.origin.y,
            bboxWidth: bbox.size.width,
            bboxHeight: bbox.size.height,
            confidence: confidence,
            rawBytes: rawBytes
        )
    }

    private func makeValidator() -> PayloadValidator {
        PayloadValidator(pattern: PayloadValidator.celDefaultPattern)
    }

    // MARK: - Tests

    func test_revalidate_emptyInput_returnsEmpty() {
        let validator = makeValidator()
        XCTAssertTrue(validator.revalidate(rawPayloads: []).isEmpty)
    }

    func test_revalidate_nilPayload_producesDecodeFailed() {
        let validator = makeValidator()
        let bbox = CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.1)
        let raw = makeRaw(payload: nil, confidence: 0.9, bbox: bbox)

        let cells = validator.revalidate(rawPayloads: [raw])

        XCTAssertEqual(cells.count, 1)
        let cell = cells[0]
        XCTAssertEqual(cell.row, -1)
        XCTAssertEqual(cell.col, -1)
        XCTAssertNil(cell.userOverride)
        XCTAssertFalse(cell.userAdded)
        guard case let .unreadable(reason, returnedBox) = cell.status else {
            return XCTFail("Expected .unreadable, got \(cell.status)")
        }
        XCTAssertEqual(reason, .decodeFailed)
        XCTAssertEqual(returnedBox, bbox)
    }

    func test_revalidate_matchingHighConfidence_producesDecoded() {
        let validator = makeValidator()
        let bbox = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let raw = makeRaw(payload: "A00011", confidence: 0.99, bbox: bbox)

        let cells = validator.revalidate(rawPayloads: [raw])

        XCTAssertEqual(cells.count, 1)
        guard case let .decoded(detected) = cells[0].status else {
            return XCTFail("Expected .decoded, got \(cells[0].status)")
        }
        XCTAssertEqual(detected.payload, "A00011")
        XCTAssertEqual(detected.boundingBox, bbox)
        XCTAssertEqual(detected.confidence, 0.99, accuracy: 1e-6)
        XCTAssertEqual(cells[0].row, -1)
        XCTAssertEqual(cells[0].col, -1)
    }

    func test_revalidate_matchingLowConfidence_producesLowConfidence() {
        let validator = makeValidator()
        // Just below the 0.5 floor.
        let raw = makeRaw(payload: "A00011", confidence: 0.49)

        let cells = validator.revalidate(rawPayloads: [raw])

        XCTAssertEqual(cells.count, 1)
        guard case let .unreadable(reason, _) = cells[0].status else {
            return XCTFail("Expected .unreadable, got \(cells[0].status)")
        }
        guard case let .lowConfidence(payload, confidence) = reason else {
            return XCTFail("Expected .lowConfidence, got \(reason)")
        }
        XCTAssertEqual(payload, "A00011")
        XCTAssertEqual(confidence, 0.49, accuracy: 1e-6)
    }

    func test_revalidate_atConfidenceFloor_isDecoded() {
        let validator = makeValidator()
        let raw = makeRaw(
            payload: "A00011",
            confidence: PayloadValidator.confidenceFloor
        )

        let cells = validator.revalidate(rawPayloads: [raw])

        guard case .decoded = cells[0].status else {
            return XCTFail("Expected .decoded at confidence floor, got \(cells[0].status)")
        }
    }

    func test_revalidate_nonMatchingPayload_producesValidatorRejected() {
        let validator = makeValidator()
        let bbox = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let raw = makeRaw(payload: "AOO011", confidence: 0.95, bbox: bbox)

        let cells = validator.revalidate(rawPayloads: [raw])

        XCTAssertEqual(cells.count, 1)
        guard case let .unreadable(reason, returnedBox) = cells[0].status else {
            return XCTFail("Expected .unreadable, got \(cells[0].status)")
        }
        XCTAssertEqual(reason, .validatorRejected(decodedPayload: "AOO011"))
        XCTAssertEqual(returnedBox, bbox)
    }

    func test_revalidate_nonMatchingButLowConfidence_prefersValidatorRejected() {
        // Validator-rejected wins over low-confidence: the regex partition
        // happens before the confidence floor is consulted, since the
        // confidence floor is only relevant when the payload would otherwise
        // be presented as `.decoded`.
        let validator = makeValidator()
        let raw = makeRaw(payload: "AOO011", confidence: 0.1)

        let cells = validator.revalidate(rawPayloads: [raw])

        guard case let .unreadable(reason, _) = cells[0].status else {
            return XCTFail("Expected .unreadable, got \(cells[0].status)")
        }
        XCTAssertEqual(reason, .validatorRejected(decodedPayload: "AOO011"))
    }

    func test_revalidate_preservesOrderAndCount() {
        let validator = makeValidator()
        let raws: [StoredRawPayload] = [
            makeRaw(payload: "A00011"),
            makeRaw(payload: nil),
            makeRaw(payload: "AOO011"),
            makeRaw(payload: "B00042", confidence: 0.4)
        ]

        let cells = validator.revalidate(rawPayloads: raws)

        XCTAssertEqual(cells.count, 4)
        if case .decoded = cells[0].status {} else { XCTFail("idx 0 should be .decoded") }
        if case .unreadable(.decodeFailed, _) = cells[1].status {} else {
            XCTFail("idx 1 should be .decodeFailed")
        }
        if case .unreadable(.validatorRejected, _) = cells[2].status {} else {
            XCTFail("idx 2 should be .validatorRejected")
        }
        if case .unreadable(.lowConfidence, _) = cells[3].status {} else {
            XCTFail("idx 3 should be .lowConfidence")
        }
    }

    func test_revalidate_doesNotMutateInput() {
        let validator = makeValidator()
        let originalBytes = Data([0x01, 0x02, 0x03])
        let raw = makeRaw(
            payload: "A00011",
            confidence: 0.8,
            bbox: CGRect(x: 0.11, y: 0.22, width: 0.33, height: 0.44),
            rawBytes: originalBytes
        )
        let snapshotID = raw.id
        let snapshotPayload = raw.payload
        let snapshotConfidence = raw.confidence
        let snapshotX = raw.bboxX
        let snapshotY = raw.bboxY
        let snapshotW = raw.bboxWidth
        let snapshotH = raw.bboxHeight
        let snapshotBytes = raw.rawBytes

        _ = validator.revalidate(rawPayloads: [raw])

        XCTAssertEqual(raw.id, snapshotID)
        XCTAssertEqual(raw.payload, snapshotPayload)
        XCTAssertEqual(raw.confidence, snapshotConfidence)
        XCTAssertEqual(raw.bboxX, snapshotX)
        XCTAssertEqual(raw.bboxY, snapshotY)
        XCTAssertEqual(raw.bboxWidth, snapshotW)
        XCTAssertEqual(raw.bboxHeight, snapshotH)
        XCTAssertEqual(raw.rawBytes, snapshotBytes)
    }

    func test_revalidate_propagatesRawBytesToDecodedCell() {
        let validator = makeValidator()
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let raw = makeRaw(payload: "A00011", confidence: 0.9, rawBytes: bytes)

        let cells = validator.revalidate(rawPayloads: [raw])

        guard case let .decoded(detected) = cells[0].status else {
            return XCTFail("Expected .decoded, got \(cells[0].status)")
        }
        XCTAssertEqual(detected.rawBytes, bytes)
    }

    func test_revalidate_regexChange_changesVerdictWithoutMutation() {
        // Capture-time validator rejects "AB1234"; a later validator accepts it.
        let captureValidator = PayloadValidator(pattern: #"^[A-Z]\d{5}$"#)
        let newValidator = PayloadValidator(pattern: #"^[A-Z]{2}\d{4}$"#)
        let raw = makeRaw(payload: "AB1234", confidence: 0.9)

        let captureCells = captureValidator.revalidate(rawPayloads: [raw])
        let newCells = newValidator.revalidate(rawPayloads: [raw])

        if case .unreadable(.validatorRejected, _) = captureCells[0].status {} else {
            XCTFail("Capture-time should be validator-rejected")
        }
        if case .decoded = newCells[0].status {} else {
            XCTFail("New regex should produce decoded")
        }
        // Input remains unchanged.
        XCTAssertEqual(raw.payload, "AB1234")
    }
}
