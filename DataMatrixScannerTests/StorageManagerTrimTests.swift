import Foundation
import SwiftData
import UIKit
import XCTest
@testable import DataMatrixScanner

/// `trim()` and integration coverage. Save/load/delete in `StorageManagerTests`.
@MainActor
final class StorageManagerTrimTests: StorageManagerTestCase {

    func testTrimRemovesAgedPhotosButKeepsRecord() async throws {
        // Now is 100 days after the scan timestamp. Default retention is 30.
        let scanTime = Date(timeIntervalSince1970: 1_000_000)
        let now = scanTime.addingTimeInterval(100 * 86_400)
        let manager = try makeManager(clock: { now })

        let result = makeScanResult(timestamp: scanTime, annotated: true)
        _ = try await manager.save(result)

        let dir = manager.directory(for: result.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        let report = try await manager.trim()

        XCTAssertEqual(report.scansTrimmed, 1)
        XCTAssertGreaterThan(report.bytesReclaimed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        if case let .ageExceeded(scanID, ageDays) = report.reasons.first {
            XCTAssertEqual(scanID, result.id)
            XCTAssertEqual(ageDays, 100)
        } else {
            XCTFail("expected .ageExceeded, got \(report.reasons)")
        }

        // Record persists with paths nilled.
        let loaded = try await manager.load(id: result.id)
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.sourceImagePath)
        XCTAssertNil(loaded?.annotatedImagePath)
    }

    func testTrimSkipsPinnedScans() async throws {
        let scanTime = Date(timeIntervalSince1970: 1_000_000)
        let now = scanTime.addingTimeInterval(60 * 86_400)
        let manager = try makeManager(clock: { now })

        let result = makeScanResult(timestamp: scanTime)
        _ = try await manager.save(result)
        _ = try await manager.pinForTesting(id: result.id)

        let report = try await manager.trim()

        XCTAssertEqual(report.scansTrimmed, 0)
        let loaded = try await manager.load(id: result.id)
        XCTAssertNotNil(loaded?.sourceImagePath)
        let dir = manager.directory(for: result.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testTrimEnforcesStorageCapOldestFirst() async throws {
        // Set a tiny cap so any single saved scan blows past it.
        UserDefaultsSettingsWriter(defaults: defaults).setMaxStorageBytes(100)

        // Anchor "now" near the scan timestamps so the age gate doesn't
        // also fire and we exercise the storage-cap path specifically.
        let base = Date(timeIntervalSince1970: 100_000)
        let now = base.addingTimeInterval(60)
        let manager = try makeManager(clock: { now })

        let oldID = UUID()
        let midID = UUID()
        let newID = UUID()
        _ = try await manager.save(makeScanResult(
            id: oldID,
            timestamp: base.addingTimeInterval(-30)
        ))
        _ = try await manager.save(makeScanResult(
            id: midID,
            timestamp: base.addingTimeInterval(-20)
        ))
        _ = try await manager.save(makeScanResult(
            id: newID,
            timestamp: base
        ))

        let report = try await manager.trim()

        XCTAssertGreaterThanOrEqual(report.scansTrimmed, 1)
        let trimmedIDs = report.reasons.compactMap { reason -> UUID? in
            if case let .storageCapExceeded(scanID) = reason { return scanID }
            return nil
        }
        XCTAssertTrue(trimmedIDs.contains(oldID))

        // Records persist; the oldest's photo path is nil.
        let loaded = try await manager.load(id: oldID)
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.sourceImagePath)
    }

    func testTrimIsNoOpWhenNothingExceedsGates() async throws {
        let manager = try makeManager()
        _ = try await manager.save(makeScanResult())

        let report = try await manager.trim()

        XCTAssertEqual(report, TrimReport.empty)
    }

    func testSaveAfterTrimReusesNoState() async throws {
        let scanTime = Date(timeIntervalSince1970: 1_000_000)
        let now = scanTime.addingTimeInterval(60 * 86_400)
        let manager = try makeManager(clock: { now })

        let first = makeScanResult(timestamp: scanTime)
        _ = try await manager.save(first)
        _ = try await manager.trim()

        // A new scan saves cleanly; its directory is created fresh.
        let second = makeScanResult()
        let stored = try await manager.save(second)
        let dir = manager.directory(for: stored.id)
        let inputURL = dir.appending(path: "input.jpg", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))

        // Both records are listable; the trimmed one has nil path.
        let all = try await manager.listAll()
        XCTAssertEqual(all.count, 2)
        let firstLoaded = all.first { $0.id == first.id }
        XCTAssertNotNil(firstLoaded)
        XCTAssertNil(firstLoaded?.sourceImagePath)
    }
}
