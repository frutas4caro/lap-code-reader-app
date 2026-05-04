import XCTest
import UIKit
@testable import DataMatrixScanner

final class ScanPipelineTests: XCTestCase {
    // MARK: - Helpers

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func collect(
        image: UIImage,
        layout: BoxLayout,
        pattern: String = "^[A-Z]\\d{5}$"
    ) async -> [PipelineEvent] {
        let pipeline = ScanPipeline()
        let stream = await pipeline.run(
            image: image,
            layout: layout,
            validatorPattern: pattern
        )
        var events: [PipelineEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - Tests

    func testFixedLayoutPartialCarriesEmptyGrid() async {
        let events = await collect(image: makeImage(), layout: .fixed(rows: 2, cols: 3))

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

    func testAutoLayoutPartialHasEmptyCells() async {
        let events = await collect(image: makeImage(), layout: .auto)

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

    func testFirstEventIsAnalyzingQualityAndLastIsComplete() async {
        let events = await collect(image: makeImage(), layout: .fixed(rows: 1, cols: 1))

        guard case .stage(.analyzingQuality) = events.first else {
            XCTFail("Expected first event to be .stage(.analyzingQuality), got \(String(describing: events.first))")
            return
        }
        guard case .complete = events.last else {
            XCTFail("Expected last event to be .complete, got \(String(describing: events.last))")
            return
        }
    }

    func testHappyPathNeverEmitsFailed() async {
        let events = await collect(image: makeImage(), layout: .fixed(rows: 9, cols: 9))

        let failed = events.contains { event in
            if case .failed = event { return true }
            return false
        }
        XCTAssertFalse(failed)
    }

    func testValidatorRegexIsCapturedOnScanResult() async {
        let pattern = "^XYZ-\\d{4}$"
        let events = await collect(image: makeImage(), layout: .auto, pattern: pattern)

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

    func testStagesEmittedInDocumentedOrder() async {
        let events = await collect(image: makeImage(), layout: .fixed(rows: 1, cols: 1))

        let stages = events.compactMap { event -> PipelineStage? in
            if case let .stage(stage) = event { return stage }
            return nil
        }
        XCTAssertEqual(
            stages,
            [.analyzingQuality, .decoding, .validating, .inferringGrid, .annotating, .exporting, .saving]
        )
    }

    func testCompleteScanResultMatchesPartialShape() async {
        let events = await collect(image: makeImage(), layout: .fixed(rows: 2, cols: 2))

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
}
