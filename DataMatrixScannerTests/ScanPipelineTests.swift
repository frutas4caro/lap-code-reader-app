import XCTest
import UIKit
import CoreGraphics
@testable import DataMatrixScanner

final class ScanPipelineTests: XCTestCase {
    // MARK: - Helpers

    private func makeCGImage(width: Int = 256, height: Int = 256) -> CGImage {
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
            fatalError("Failed to construct CGContext for test fixture")
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("Failed to render CGImage for test fixture")
        }
        return image
    }

    private func collect(
        cgImage: CGImage,
        layout: BoxLayout,
        pattern: String = "^[A-Z]\\d{5}$"
    ) async -> [PipelineEvent] {
        let pipeline = ScanPipeline()
        let stream = await pipeline.run(
            cgImage: cgImage,
            layout: layout,
            validatorPattern: pattern
        )
        var events: [PipelineEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    /// Older Apple simulators raise Vision domain code 9 ("Could not
    /// create inference context") for any input. The pipeline forwards
    /// that as `.failed(.decodeFailed(...))`. Tests that depend on a
    /// successful happy path skip when this environment shows up.
    private func skipIfVisionUnavailable(_ events: [PipelineEvent]) throws {
        for event in events {
            if case let .failed(.decodeFailed(underlying)) = event {
                let nsError = underlying as NSError
                if nsError.domain == "com.apple.Vision" && nsError.code == 9 {
                    throw XCTSkip("Vision inference context unavailable in this simulator (\(nsError.localizedDescription)).")
                }
            }
        }
    }

    // MARK: - Tests

    func testFixedLayoutPartialCarriesEmptyGrid() async throws {
        // BarcodeScanner returns [] in the simulator, so a 2x3 fixed
        // layout must still produce 6 .empty cells.
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 2, cols: 3))
        try skipIfVisionUnavailable(events)

        let partials = events.compactMap { event -> ScanResult? in
            if case let .partial(result) = event { return result }
            return nil
        }
        XCTAssertEqual(partials.count, 1)
        guard let partial = partials.first else {
            XCTFail("Expected a partial ScanResult")
            return
        }
        XCTAssertEqual(partial.cells.count, 6)
        XCTAssertTrue(partial.cells.allSatisfy { $0.status == .empty })
        XCTAssertNil(partial.annotatedImage)
    }

    func testFixed2x2PartialHasFourEmptyCells() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 2, cols: 2))
        try skipIfVisionUnavailable(events)
        guard case let .partial(partial)? = events.first(where: {
            if case .partial = $0 { return true }
            return false
        }) else {
            XCTFail("Expected a .partial event")
            return
        }
        XCTAssertEqual(partial.cells.count, 4)
        XCTAssertTrue(partial.cells.allSatisfy { $0.status == .empty })
    }

    func testAutoLayoutPartialHasEmptyCells() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .auto)
        try skipIfVisionUnavailable(events)

        guard case let .partial(partial)? = events.first(where: {
            if case .partial = $0 { return true }
            return false
        }) else {
            XCTFail("Expected a .partial event")
            return
        }
        XCTAssertEqual(partial.cells, [])
        XCTAssertNil(partial.quality.expectedCount)
    }

    func testFirstEventIsAnalyzingQualityAndLastIsComplete() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 1, cols: 1))
        try skipIfVisionUnavailable(events)

        guard case .stage(.analyzingQuality) = events.first else {
            XCTFail("Expected first event to be .stage(.analyzingQuality), got \(String(describing: events.first))")
            return
        }
        guard case .complete = events.last else {
            XCTFail("Expected last event to be .complete, got \(String(describing: events.last))")
            return
        }
    }

    func testHappyPathNeverEmitsFailed() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 9, cols: 9))
        try skipIfVisionUnavailable(events)

        let failed = events.contains { event in
            if case .failed = event { return true }
            return false
        }
        XCTAssertFalse(failed)
    }

    func testValidatorRegexIsCapturedOnScanResult() async throws {
        let pattern = "^XYZ-\\d{4}$"
        let events = await collect(cgImage: makeCGImage(), layout: .auto, pattern: pattern)
        try skipIfVisionUnavailable(events)

        let regexes = events.compactMap { event -> String? in
            switch event {
            case let .partial(result), let .complete(result):
                return result.validatorRegex
            default:
                return nil
            }
        }
        XCTAssertFalse(regexes.isEmpty)
        XCTAssertTrue(regexes.allSatisfy { $0 == pattern })
    }

    func testStagesEmittedInDocumentedOrder() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 1, cols: 1))
        try skipIfVisionUnavailable(events)

        let stages = events.compactMap { event -> PipelineStage? in
            if case let .stage(stage) = event { return stage }
            return nil
        }
        XCTAssertEqual(
            stages,
            [.analyzingQuality, .decoding, .validating, .inferringGrid, .annotating, .exporting, .saving]
        )
    }

    func testCompleteScanResultMatchesPartialShape() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 2, cols: 2))
        try skipIfVisionUnavailable(events)

        var partialCellCount: Int?
        var completeCellCount: Int?
        for event in events {
            switch event {
            case let .partial(result):
                partialCellCount = result.cells.count
            case let .complete(result):
                completeCellCount = result.cells.count
            default:
                break
            }
        }
        XCTAssertEqual(partialCellCount, 4)
        XCTAssertEqual(completeCellCount, 4)
    }

    func testCSVMatchesCSVExporterOutput() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 2, cols: 2))
        try skipIfVisionUnavailable(events)
        guard case let .partial(partial)? = events.first(where: {
            if case .partial = $0 { return true }
            return false
        }) else {
            XCTFail("Expected a .partial event")
            return
        }
        let expected = CSVExporter().export(cells: partial.cells)
        XCTAssertEqual(partial.csv, expected)
    }

    func testAnnotatedEventEmittedAndCarriedOnComplete() async throws {
        let events = await collect(cgImage: makeCGImage(), layout: .fixed(rows: 1, cols: 1))
        try skipIfVisionUnavailable(events)
        let hasAnnotated = events.contains { event in
            if case .annotated = event { return true }
            return false
        }
        XCTAssertTrue(hasAnnotated)

        guard case let .complete(result)? = events.last else {
            XCTFail("Expected last event to be .complete")
            return
        }
        XCTAssertNotNil(result.annotatedImage)
    }
}
