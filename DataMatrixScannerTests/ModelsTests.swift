import XCTest
@testable import DataMatrixScanner

final class ModelsTests: XCTestCase {

    // MARK: - DetectedCode

    func testDetectedCodeDerivesCentroidFromBoundingBox() {
        let bbox = CGRect(x: 0.2, y: 0.4, width: 0.1, height: 0.1)
        let code = DetectedCode(payload: "A00011", boundingBox: bbox, confidence: 0.95)
        XCTAssertEqual(code.centroid.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(code.centroid.y, 0.45, accuracy: 1e-9)
        XCTAssertNil(code.rawBytes)
    }

    // MARK: - BoxLayout

    func testBoxLayoutStorageStringRoundTrip() {
        XCTAssertEqual(BoxLayout.auto.storageString, "auto")
        XCTAssertEqual(BoxLayout.fixed(rows: 9, cols: 9).storageString, "9x9")
        XCTAssertEqual(BoxLayout.fromStorageString("auto"), .auto)
        XCTAssertEqual(BoxLayout.fromStorageString("9x9"), .fixed(rows: 9, cols: 9))
        XCTAssertNil(BoxLayout.fromStorageString("nope"))
        XCTAssertNil(BoxLayout.fromStorageString("0x9"))
    }

    func testBoxLayoutCodableRoundTrip() throws {
        let layout = BoxLayout.fixed(rows: 9, cols: 9)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(BoxLayout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }

    // MARK: - GridCell

    func testGridCellOutlierFlag() {
        let bbox = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let detected = DetectedCode(payload: "Z99999", boundingBox: bbox, confidence: 1.0)
        let outlier = GridCell(row: -1, col: -1, status: .decoded(detected))
        XCTAssertTrue(outlier.isOutlier)
        let placed = GridCell(row: 1, col: 1, status: .empty)
        XCTAssertFalse(placed.isOutlier)
        XCTAssertNil(placed.userOverride)
        XCTAssertFalse(placed.userAdded)
    }

    // MARK: - CellStatus

    func testCellStatusEqualityAcrossUnreadableReasons() {
        let bbox = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let lhs = CellStatus.unreadable(reason: .validatorRejected(decodedPayload: "AOO011"), boundingBox: bbox)
        let rhs = CellStatus.unreadable(reason: .validatorRejected(decodedPayload: "AOO011"), boundingBox: bbox)
        let other = CellStatus.unreadable(reason: .decodeFailed, boundingBox: bbox)
        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }

    // MARK: - UnplacedDetection

    func testUnplacedDetectionDefaultActionIsNone() {
        let bbox = CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.05)
        let unplaced = UnplacedDetection(
            payload: "Z99999",
            boundingBox: bbox,
            confidence: 0.9,
            reason: .spatialOutlier
        )
        XCTAssertEqual(unplaced.action, .none)
        XCTAssertNil(unplaced.rawBytes)
    }

    func testUnplacedDetectionDecodeFailedHasNilPayload() {
        let bbox = CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)
        let unplaced = UnplacedDetection(
            payload: nil,
            boundingBox: bbox,
            confidence: 0.0,
            reason: .decodeFailed
        )
        XCTAssertNil(unplaced.payload)
    }

    // MARK: - ScanQualityReport / Warnings

    func testQualityReportCarriesWarnings() {
        let report = ScanQualityReport(
            decodedCount: 70,
            rejectedByValidatorCount: 3,
            expectedCount: 81,
            outlierCount: 1,
            principalAxisAngle: 30.0,
            confidenceFloor: 0.6,
            warnings: [
                .lowDecodeRatio(decoded: 70, expected: 81),
                .outliersDetected(count: 1)
            ]
        )
        XCTAssertEqual(report.warnings.count, 2)
        XCTAssertEqual(report.expectedCount, 81)
    }

    // MARK: - ScanError

    func testScanErrorHasNoNoCodesFoundCase() {
        // Compile-time guarantee: only the three documented cases exist.
        // Exhaustive switch will fail to compile if a case is added.
        let error = ScanError.permissionDenied
        switch error {
        case .permissionDenied, .imageTooLarge, .decodeFailed:
            XCTAssertTrue(true)
        }
    }

    // MARK: - StoredScan defaults

    func testStoredScanDefaultsAreEmpty() {
        let scan = StoredScan(
            layoutMode: BoxLayout.fixed(rows: 9, cols: 9).storageString,
            validatorRegexAtCapture: "^[A-Z]\\d{5}$"
        )
        XCTAssertNil(scan.sourceImagePath)
        XCTAssertNil(scan.annotatedImagePath)
        XCTAssertTrue(scan.rawPayloads.isEmpty)
        XCTAssertTrue(scan.edits.isEmpty)
        XCTAssertFalse(scan.isPinned)
        XCTAssertEqual(scan.layoutMode, "9x9")
    }

    func testStoredEditKindRoundTripsThroughRawString() {
        let edit = StoredEdit(kind: .userOverride, row: 1, col: 2, newPayload: "B00042")
        XCTAssertEqual(edit.kind, .userOverride)
        XCTAssertEqual(edit.kindRaw, "userOverride")
        XCTAssertEqual(edit.newPayload, "B00042")
    }
}
