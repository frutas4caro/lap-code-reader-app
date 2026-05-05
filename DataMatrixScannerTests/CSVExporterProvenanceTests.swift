import XCTest
import CoreGraphics
@testable import DataMatrixScanner

/// Tests for the v1.1 provenance schema (`includeProvenance: true`) and the
/// v1.0 byte-for-byte regression guard.
final class CSVExporterProvenanceTests: XCTestCase {

    // MARK: - Helpers

    private func decoded(_ payload: String, row: Int, col: Int) -> GridCell {
        let code = DetectedCode(
            payload: payload,
            boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
            confidence: 1.0
        )
        return GridCell(row: row, col: col, status: .decoded(code))
    }

    private func bbox() -> CGRect {
        CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.05)
    }

    // MARK: - v1.0 regression guard

    /// `includeProvenance: false` must produce byte-identical v1.0 output.
    func testProvenanceOffMatchesLegacyByteForByte() {
        let legacy = CSVExporter()
        let new = CSVExporter(includeProvenance: false)

        var cells: [GridCell] = []
        var counter = 0
        for row in 1...3 {
            for col in 1...3 {
                counter += 1
                cells.append(decoded("A0000\(counter)", row: row, col: col))
            }
        }
        // Throw in some unreadables, an outlier, and an unplaced detection.
        cells.append(GridCell(row: 4, col: 1, status: .empty))
        cells.append(GridCell(
            row: 4, col: 2,
            status: .unreadable(reason: .decodeFailed, boundingBox: nil)
        ))
        cells.append(decoded("Z99999", row: -1, col: -1))

        let unplaced = [
            UnplacedDetection(
                payload: "Y88888",
                boundingBox: bbox(),
                confidence: 0.9,
                reason: .spatialOutlier
            )
        ]

        XCTAssertEqual(legacy.export(cells: cells), new.export(cells: cells))
        // The unplaced overload with provenance off ignores `unplaced`.
        XCTAssertEqual(
            new.export(cells: cells, unplaced: unplaced),
            legacy.export(cells: cells)
        )
    }

    func testProvenanceOffIgnoresUnplacedDetections() {
        let exporter = CSVExporter(includeProvenance: false)
        let cells = [decoded("A00001", row: 1, col: 1)]
        let unplaced = [
            UnplacedDetection(
                payload: "B00001",
                boundingBox: bbox(),
                confidence: 0.9,
                reason: .spatialOutlier
            ),
            UnplacedDetection(
                payload: nil,
                boundingBox: bbox(),
                confidence: 0.4,
                reason: .decodeFailed
            )
        ]
        let csv = exporter.export(cells: cells, unplaced: unplaced)
        XCTAssertEqual(csv, "row,col,code\n1,1,A00001\n")
        XCTAssertFalse(csv.contains("B00001"))
    }

    // MARK: - v1.1 schema basics

    func testProvenanceOnEmitsFourColumnHeader() {
        let exporter = CSVExporter(includeProvenance: true)
        let csv = exporter.export(cells: [])
        XCTAssertEqual(csv, "row,col,code,status\n")
    }

    func testDecodedCellStatusIsDecoded() {
        let exporter = CSVExporter(includeProvenance: true)
        let csv = exporter.export(cells: [decoded("A00011", row: 1, col: 1)])
        XCTAssertEqual(csv, "row,col,code,status\n1,1,A00011,decoded\n")
    }

    func testEmptyCellStatusIsEmpty() {
        let exporter = CSVExporter(includeProvenance: true)
        let cell = GridCell(row: 1, col: 2, status: .empty)
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code,status\n1,2,null,empty\n")
    }

    func testUnreadableDecodeFailedStatus() {
        let exporter = CSVExporter(includeProvenance: true)
        let cell = GridCell(
            row: 2, col: 1,
            status: .unreadable(reason: .decodeFailed, boundingBox: nil)
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code,status\n2,1,null,unreadable:decode_failed\n")
    }

    func testValidatorRejectedStatusIncludesPayload() {
        let exporter = CSVExporter(includeProvenance: true)
        let cell = GridCell(
            row: 2, col: 2,
            status: .unreadable(
                reason: .validatorRejected(decodedPayload: "AOO011"),
                boundingBox: nil
            )
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(
            csv,
            "row,col,code,status\n2,2,null,unreadable:rejected(AOO011)\n"
        )
    }

    func testLowConfidenceStatusIncludesPayload() {
        let exporter = CSVExporter(includeProvenance: true)
        let cell = GridCell(
            row: 3, col: 3,
            status: .unreadable(
                reason: .lowConfidence(payload: "A00011", confidence: 0.2),
                boundingBox: nil
            )
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(
            csv,
            "row,col,code,status\n3,3,null,unreadable:low_confidence(A00011)\n"
        )
    }

    func testUserOverrideProducesEditedStatus() {
        let exporter = CSVExporter(includeProvenance: true)
        var cell = decoded("A00011", row: 1, col: 3)
        cell.userOverride = "X12345"
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code,status\n1,3,X12345,edited\n")
    }

    func testUserAddedProducesManualStatus() {
        let exporter = CSVExporter(includeProvenance: true)
        var cell = decoded("X12345", row: 2, col: 3)
        cell.userAdded = true
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code,status\n2,3,X12345,manual\n")
    }

    // MARK: - Outliers

    func testCellOutlierEmitsNullRowColAndDecodedOutlierStatus() {
        let exporter = CSVExporter(includeProvenance: true)
        let outlier = decoded("Z99999", row: -1, col: -1)
        let csv = exporter.export(cells: [outlier])
        XCTAssertEqual(
            csv,
            "row,col,code,status\nnull,null,Z99999,decoded:outlier\n"
        )
    }

    func testSpatialOutlierUnplacedDetectionEmitsDecodedOutlier() {
        let exporter = CSVExporter(includeProvenance: true)
        let det = UnplacedDetection(
            payload: "Y88888",
            boundingBox: bbox(),
            confidence: 0.9,
            reason: .spatialOutlier
        )
        let csv = exporter.export(cells: [], unplaced: [det])
        XCTAssertEqual(
            csv,
            "row,col,code,status\nnull,null,Y88888,decoded:outlier\n"
        )
    }

    func testValidatorRejectedOutlierUnplacedDetectionEmitsRejected() {
        let exporter = CSVExporter(includeProvenance: true)
        let det = UnplacedDetection(
            payload: "AOO011",
            boundingBox: bbox(),
            confidence: 0.9,
            reason: .validatorRejectedOutlier(decodedPayload: "AOO011")
        )
        let csv = exporter.export(cells: [], unplaced: [det])
        XCTAssertEqual(
            csv,
            "row,col,code,status\nnull,null,null,unreadable:rejected(AOO011)\n"
        )
    }

    func testDecodeFailedUnplacedDetectionEmitsDecodeFailed() {
        let exporter = CSVExporter(includeProvenance: true)
        let det = UnplacedDetection(
            payload: nil,
            boundingBox: bbox(),
            confidence: 0.3,
            reason: .decodeFailed
        )
        let csv = exporter.export(cells: [], unplaced: [det])
        XCTAssertEqual(
            csv,
            "row,col,code,status\nnull,null,null,unreadable:decode_failed\n"
        )
    }

    func testDiscardedUnplacedDetectionEmitsDiscardedStatus() {
        let exporter = CSVExporter(includeProvenance: true)
        let det = UnplacedDetection(
            payload: "Q12345",
            boundingBox: bbox(),
            confidence: 0.9,
            reason: .spatialOutlier,
            action: .discarded
        )
        let csv = exporter.export(cells: [], unplaced: [det])
        XCTAssertEqual(
            csv,
            "row,col,code,status\nnull,null,Q12345,discarded\n"
        )
    }

    // MARK: - Sort ordering

    func testRegularRowsPrecedeNullRowOutliers() {
        let exporter = CSVExporter(includeProvenance: true)
        let cellOutlier = decoded("Z99999", row: -1, col: -1)
        let regularA = decoded("A00001", row: 1, col: 1)
        let regularB = decoded("A00002", row: 2, col: 2)
        let unplaced = UnplacedDetection(
            payload: "Y88888",
            boundingBox: bbox(),
            confidence: 0.9,
            reason: .spatialOutlier
        )

        let csv = exporter.export(
            cells: [cellOutlier, regularB, regularA],
            unplaced: [unplaced]
        )
        let expected = """
        row,col,code,status
        1,1,A00001,decoded
        2,2,A00002,decoded
        null,null,Z99999,decoded:outlier
        null,null,Y88888,decoded:outlier

        """
        XCTAssertEqual(csv, expected)
    }

    func testDeterministicSortAcrossRuns() {
        let exporter = CSVExporter(includeProvenance: true)
        let cells: [GridCell] = [
            decoded("A00006", row: 3, col: 2),
            decoded("A00002", row: 1, col: 2),
            decoded("A00003", row: 2, col: 1),
            decoded("A00001", row: 1, col: 1),
            decoded("A00005", row: 3, col: 1),
            decoded("A00004", row: 2, col: 2)
        ]
        let first = exporter.export(cells: cells)
        let second = exporter.export(cells: cells)
        XCTAssertEqual(first, second)
        let expected = """
        row,col,code,status
        1,1,A00001,decoded
        1,2,A00002,decoded
        2,1,A00003,decoded
        2,2,A00004,decoded
        3,1,A00005,decoded
        3,2,A00006,decoded

        """
        XCTAssertEqual(first, expected)
    }

    // MARK: - Combined fixture

}

/// Combined-fixture tests kept in a separate class to satisfy
/// `type_body_length` while still exercising the full v1.1 schema.
final class CSVExporterProvenanceFixtureTests: XCTestCase {

    private func decoded(_ payload: String, row: Int, col: Int) -> GridCell {
        let code = DetectedCode(
            payload: payload,
            boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
            confidence: 1.0
        )
        return GridCell(row: row, col: col, status: .decoded(code))
    }

    func testFullProvenanceScenarioMatchesSpecExample() {
        let exporter = CSVExporter(includeProvenance: true)
        var edited = decoded("A00010", row: 1, col: 3)
        edited.userOverride = "B00042"
        var manual = decoded("X12345", row: 2, col: 3)
        manual.userAdded = true

        let cells: [GridCell] = [
            decoded("A00011", row: 1, col: 1),
            GridCell(row: 1, col: 2, status: .empty),
            edited,
            GridCell(
                row: 2, col: 1,
                status: .unreadable(reason: .decodeFailed, boundingBox: nil)
            ),
            GridCell(
                row: 2, col: 2,
                status: .unreadable(
                    reason: .validatorRejected(decodedPayload: "AOO011"),
                    boundingBox: nil
                )
            ),
            manual,
            decoded("Z99999", row: -1, col: -1)
        ]

        let csv = exporter.export(cells: cells)
        let expected = """
        row,col,code,status
        1,1,A00011,decoded
        1,2,null,empty
        1,3,B00042,edited
        2,1,null,unreadable:decode_failed
        2,2,null,unreadable:rejected(AOO011)
        2,3,X12345,manual
        null,null,Z99999,decoded:outlier

        """
        XCTAssertEqual(csv, expected)
    }
}
