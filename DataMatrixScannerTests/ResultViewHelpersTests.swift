import XCTest
@testable import DataMatrixScanner

/// Covers the testable helpers on `ResultView` — the stage-label
/// mapping and the temp-file writer the share button uses. The
/// SwiftUI body is exercised by integration / snapshot work in v1.1.
final class ResultViewHelpersTests: XCTestCase {

    // MARK: - friendlyStageLabel

    func testFriendlyStageLabel_nilReturnsGenericWorking() {
        XCTAssertEqual(ResultView.friendlyStageLabel(nil), "Working…")
    }

    func testFriendlyStageLabel_analyzingQuality() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.analyzingQuality), "Analyzing quality…")
    }

    func testFriendlyStageLabel_decoding() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.decoding), "Decoding…")
    }

    func testFriendlyStageLabel_validating() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.validating), "Validating…")
    }

    func testFriendlyStageLabel_inferringGrid() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.inferringGrid), "Inferring grid…")
    }

    func testFriendlyStageLabel_annotating() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.annotating), "Annotating…")
    }

    func testFriendlyStageLabel_exporting() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.exporting), "Exporting…")
    }

    func testFriendlyStageLabel_saving() {
        XCTAssertEqual(ResultView.friendlyStageLabel(.saving), "Saving…")
    }

    // MARK: - writeCSVToTempFile

    func testWriteCSVToTempFile_writesExactBytes() throws {
        let csv = "row,col,code\n1,1,A00011\n1,2,null\n"
        let filename = "DataMatrix_unit_test_\(UUID().uuidString).csv"
        let url = try ResultView.writeCSVToTempFile(csv, filename: filename)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let roundTripped = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(roundTripped, csv)
    }

    func testWriteCSVToTempFile_returnsURLWithExpectedFilename() throws {
        let filename = "DataMatrix_2026-04-26T143022.csv"
        let url = try ResultView.writeCSVToTempFile("row,col,code\n", filename: filename)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, filename)
        XCTAssertEqual(url.pathExtension, "csv")
    }

    func testWriteCSVToTempFile_writesUnderTemporaryDirectory() throws {
        let url = try ResultView.writeCSVToTempFile("a,b,c\n", filename: "tmp_\(UUID().uuidString).csv")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(tempPath))
    }

    func testWriteCSVToTempFile_overwritesExistingFile() throws {
        let filename = "overwrite_\(UUID().uuidString).csv"
        let first = try ResultView.writeCSVToTempFile("first\n", filename: filename)
        let second = try ResultView.writeCSVToTempFile("second\n", filename: filename)
        addTeardownBlock { try? FileManager.default.removeItem(at: second) }

        XCTAssertEqual(first.path, second.path)
        let contents = try String(contentsOf: second, encoding: .utf8)
        XCTAssertEqual(contents, "second\n")
    }

    func testWriteCSVToTempFile_handlesEmptyCSV() throws {
        let url = try ResultView.writeCSVToTempFile("", filename: "empty_\(UUID().uuidString).csv")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "")
    }

    // MARK: - failureMessage

    func testFailureMessage_permissionDenied() {
        let msg = ResultView.failureMessage(for: .permissionDenied)
        XCTAssertTrue(msg.lowercased().contains("permission"))
    }

    func testFailureMessage_imageTooLarge() {
        let msg = ResultView.failureMessage(for: .imageTooLarge)
        XCTAssertTrue(msg.lowercased().contains("large"))
    }
}
