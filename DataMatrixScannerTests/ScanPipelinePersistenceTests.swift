import CoreGraphics
import Foundation
import SwiftData
import UIKit
import XCTest
@testable import DataMatrixScanner

/// Persistence-side tests for `ScanPipeline` (dms-5f9): when a
/// `StorageManager` is injected, a successful run persists exactly one
/// `StoredScan`; when the storage layer throws, the pipeline still
/// emits `.complete` and never `.failed`.
@MainActor
final class ScanPipelinePersistenceTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCGImage(width: Int = 64, height: Int = 64) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("CGContext build failed")
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("CGImage render failed")
        }
        return image
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredScan.self, StoredRawPayload.self, StoredEdit.self])
        let config = ModelConfiguration(
            "ScanPipelinePersistenceTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// `XCTSkip` when the simulator's Vision stack returns the well-
    /// known "Could not create inference context" failure. Pipeline
    /// then routes that to `.failed(.decodeFailed)` and there's no
    /// successful run to assert against.
    private func skipIfVisionUnavailable(_ events: [PipelineEvent]) throws {
        for event in events {
            if case let .failed(.decodeFailed(underlying)) = event {
                let nsError = underlying as NSError
                if nsError.domain == "com.apple.Vision" && nsError.code == 9 {
                    throw XCTSkip("Vision inference context unavailable in this simulator.")
                }
            }
        }
    }

    private func collect(
        pipeline: ScanPipeline,
        cgImage: CGImage,
        layout: BoxLayout = .fixed(rows: 1, cols: 1)
    ) async -> [PipelineEvent] {
        let stream = await pipeline.run(
            cgImage: cgImage,
            layout: layout,
            validatorPattern: #"^[A-Z]\d{5}$"#
        )
        var events: [PipelineEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    // MARK: - Tests

    /// Happy path: with a working `StorageManager` injected, completing
    /// the pipeline writes exactly one record.
    func testStorageManagerPersistsCompletedScan() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "PipelinePersist-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let container = try makeContainer()
        let storage = StorageManager(
            container: container,
            filesystem: DirectoryFilesystem(scansRoot: tempRoot)
        )
        let pipeline = ScanPipeline(storageManager: storage)
        let events = await collect(pipeline: pipeline, cgImage: makeCGImage())
        try skipIfVisionUnavailable(events)

        let scans = try await storage.listAll()
        XCTAssertEqual(scans.count, 1, "Expected exactly one persisted StoredScan")

        let didComplete = events.contains { event in
            if case .complete = event { return true }
            return false
        }
        XCTAssertTrue(didComplete, "Pipeline should still emit .complete")
    }

    /// When the storage write throws (here forced via an unwritable
    /// filesystem root), the pipeline must swallow the error and still
    /// emit `.complete` — never `.failed`.
    func testStorageFailureDoesNotFailPipeline() async throws {
        // /dev points at a real directory but a path under /dev that
        // doesn't exist (and can't be created) makes both
        // createDirectory and write throw on a normal sandbox.
        let unwritable = URL(fileURLWithPath: "/dev/null/does-not-exist", isDirectory: true)
        let container = try makeContainer()
        let storage = StorageManager(
            container: container,
            filesystem: DirectoryFilesystem(scansRoot: unwritable)
        )
        let pipeline = ScanPipeline(storageManager: storage)
        let events = await collect(pipeline: pipeline, cgImage: makeCGImage())
        try skipIfVisionUnavailable(events)

        let didFail = events.contains { event in
            if case .failed = event { return true }
            return false
        }
        XCTAssertFalse(didFail, "Storage failures must not surface as ScanError")

        let didComplete = events.contains { event in
            if case .complete = event { return true }
            return false
        }
        XCTAssertTrue(didComplete, "Pipeline should still emit .complete after a swallowed save error")

        // And nothing should be persisted.
        let scans = try await storage.listAll()
        XCTAssertEqual(scans.count, 0)
    }
}
