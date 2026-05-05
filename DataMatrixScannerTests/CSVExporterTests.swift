import XCTest
import CoreGraphics
@testable import DataMatrixScanner

final class CSVExporterTests: XCTestCase {

    // MARK: - Helpers

    private func decodedCell(row: Int, col: Int, payload: String) -> GridCell {
        let code = DetectedCode(
            payload: payload,
            boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1),
            confidence: 1.0
        )
        return GridCell(row: row, col: col, status: .decoded(code))
    }

    // MARK: - Tests

    func testEmptyCellsReturnsHeaderOnly() {
        let exporter = CSVExporter()
        XCTAssertEqual(exporter.export(cells: []), "row,col,code\n")
    }

    func test3x3DecodedGridSortedByRowThenCol() {
        let exporter = CSVExporter()
        var cells: [GridCell] = []
        var counter = 0
        for row in 1...3 {
            for col in 1...3 {
                counter += 1
                cells.append(decodedCell(row: row, col: col, payload: "A0000\(counter)"))
            }
        }
        let csv = exporter.export(cells: cells)
        let expected = """
        row,col,code
        1,1,A00001
        1,2,A00002
        1,3,A00003
        2,1,A00004
        2,2,A00005
        2,3,A00006
        3,1,A00007
        3,2,A00008
        3,3,A00009

        """
        XCTAssertEqual(csv, expected)
    }

    func testUserOverrideTakesPrecedenceOverDecodedPayload() {
        let exporter = CSVExporter()
        var cell = decodedCell(row: 1, col: 1, payload: "A00011")
        cell.userOverride = "X12345"
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code\n1,1,X12345\n")
    }

    func testEmptyCellExportsNull() {
        let exporter = CSVExporter()
        let cell = GridCell(row: 2, col: 3, status: .empty)
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code\n2,3,null\n")
    }

    func testUnreadableDecodeFailedExportsNull() {
        let exporter = CSVExporter()
        let cell = GridCell(
            row: 4, col: 5,
            status: .unreadable(reason: .decodeFailed, boundingBox: nil)
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code\n4,5,null\n")
    }

    func testValidatorRejectedExportsNullNotRejectedPayload() {
        let exporter = CSVExporter()
        let cell = GridCell(
            row: 1, col: 2,
            status: .unreadable(
                reason: .validatorRejected(decodedPayload: "AOO011"),
                boundingBox: nil
            )
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code\n1,2,null\n")
        XCTAssertFalse(csv.contains("AOO011"))
    }

    func testOutlierCellOmittedFromCSV() {
        let exporter = CSVExporter()
        let outlier = decodedCell(row: -1, col: -1, payload: "Z99999")
        let normal = decodedCell(row: 1, col: 1, payload: "A00001")
        let csv = exporter.export(cells: [outlier, normal])
        XCTAssertEqual(csv, "row,col,code\n1,1,A00001\n")
        XCTAssertFalse(csv.contains("Z99999"))
    }

    func testSortIsStableWithUnorderedInput() {
        let exporter = CSVExporter()
        let cells: [GridCell] = [
            decodedCell(row: 3, col: 2, payload: "A00006"),
            decodedCell(row: 1, col: 2, payload: "A00002"),
            decodedCell(row: 2, col: 1, payload: "A00003"),
            decodedCell(row: 1, col: 1, payload: "A00001"),
            decodedCell(row: 3, col: 1, payload: "A00005"),
            decodedCell(row: 2, col: 2, payload: "A00004")
        ]
        let csv = exporter.export(cells: cells)
        let expected = """
        row,col,code
        1,1,A00001
        1,2,A00002
        2,1,A00003
        2,2,A00004
        3,1,A00005
        3,2,A00006

        """
        XCTAssertEqual(csv, expected)
    }

    func testLowConfidenceUnreadableExportsNull() {
        let exporter = CSVExporter()
        let cell = GridCell(
            row: 5, col: 5,
            status: .unreadable(
                reason: .lowConfidence(payload: "A00011", confidence: 0.2),
                boundingBox: nil
            )
        )
        let csv = exporter.export(cells: [cell])
        XCTAssertEqual(csv, "row,col,code\n5,5,null\n")
    }

    func testFilenameHelperProducesSpecExampleShape() {
        // 2026-04-26T14:30:22Z UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 26
        components.hour = 14
        components.minute = 30
        components.second = 22
        components.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            XCTFail("Failed to construct deterministic date")
            return
        }
        XCTAssertEqual(
            CSVExporter.filename(for: date),
            "DataMatrix_2026-04-26T143022.csv"
        )
    }

    func testLineEndingsAreUnix() {
        let exporter = CSVExporter()
        let cell = decodedCell(row: 1, col: 1, payload: "A00001")
        let csv = exporter.export(cells: [cell])
        XCTAssertFalse(csv.contains("\r"))
        XCTAssertEqual(csv.filter { $0 == "\n" }.count, 2)
    }
}
