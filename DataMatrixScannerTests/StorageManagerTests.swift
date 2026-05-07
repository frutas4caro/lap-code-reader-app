import Foundation
import SwiftData
import UIKit
import XCTest
@testable import DataMatrixScanner

/// Save / load / list / delete coverage. Trim is in `StorageManagerTrimTests`.
@MainActor
final class StorageManagerTests: StorageManagerTestCase {

    // MARK: - save

    func testSaveWritesInputJpegAndInsertsRecord() async throws {
        let manager = try makeManager()
        let result = makeScanResult()

        let stored = try await manager.save(result)

        let dir = manager.directory(for: result.id)
        let inputURL = dir.appending(path: "input.jpg", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))
        XCTAssertEqual(stored.id, result.id)
        XCTAssertNotNil(stored.sourceImagePath)
        XCTAssertNil(stored.annotatedImagePath)
        XCTAssertEqual(stored.layoutMode, "9x9")
        XCTAssertEqual(stored.validatorRegexAtCapture, #"^[A-Z]\d{5}$"#)

        // Bytes on disk equal the JPEG payload size.
        let onDisk = try Data(contentsOf: inputURL)
        let expected = try XCTUnwrap(result.sourceImage.jpegData(compressionQuality: 0.9))
        XCTAssertEqual(onDisk.count, expected.count)
    }

    func testSaveWritesAnnotatedJpegWhenPresent() async throws {
        let manager = try makeManager()
        let result = makeScanResult(annotated: true)

        let stored = try await manager.save(result)

        let dir = manager.directory(for: result.id)
        let annotatedURL = dir.appending(path: "annotated.jpg", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: annotatedURL.path))
        XCTAssertNotNil(stored.annotatedImagePath)
    }

    func testSaveProjectsRawPayloadsFromCells() async throws {
        let manager = try makeManager()
        let result = makeScanResult()

        let stored = try await manager.save(result)

        // 1 decoded + 2 unreadable-with-bbox = 3 raw payloads. The .empty
        // cell contributes nothing.
        XCTAssertEqual(stored.rawPayloads.count, 3)
        let payloads = stored.rawPayloads.compactMap(\.payload).sorted()
        XCTAssertEqual(payloads, ["A00011", "AOO011"])
    }

    // MARK: - load / listAll

    func testLoadRoundTripsASavedScan() async throws {
        let manager = try makeManager()
        let result = makeScanResult()
        _ = try await manager.save(result)

        let loaded = try await manager.load(id: result.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, result.id)
    }

    func testLoadMissingIdReturnsNil() async throws {
        let manager = try makeManager()
        let loaded = try await manager.load(id: UUID())
        XCTAssertNil(loaded)
    }

    func testListAllReturnsScansNewestFirst() async throws {
        let manager = try makeManager()
        let oldID = UUID()
        let midID = UUID()
        let newID = UUID()
        _ = try await manager.save(makeScanResult(
            id: oldID,
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))
        _ = try await manager.save(makeScanResult(
            id: newID,
            timestamp: Date(timeIntervalSince1970: 3_000)
        ))
        _ = try await manager.save(makeScanResult(
            id: midID,
            timestamp: Date(timeIntervalSince1970: 2_000)
        ))

        let all = try await manager.listAll()
        XCTAssertEqual(all.map(\.id), [newID, midID, oldID])
    }

    // MARK: - delete

    func testDeleteRemovesFilesAndRecord() async throws {
        let manager = try makeManager()
        let result = makeScanResult(annotated: true)
        _ = try await manager.save(result)

        let dir = manager.directory(for: result.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        try await manager.delete(id: result.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        let loaded = try await manager.load(id: result.id)
        XCTAssertNil(loaded)
    }

    func testDeleteMissingIdThrows() async throws {
        let manager = try makeManager()
        do {
            try await manager.delete(id: UUID())
            XCTFail("expected delete to throw")
        } catch StorageError.recordNotFound {
            // expected
        }
    }
}
