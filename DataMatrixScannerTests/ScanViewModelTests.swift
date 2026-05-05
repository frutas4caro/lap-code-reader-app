import CoreGraphics
import XCTest
@testable import DataMatrixScanner

@MainActor
final class ScanViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeCGImage(width: Int = 64, height: Int = 64) throws -> CGImage {
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
            throw XCTSkip("Could not allocate CGContext on this host.")
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw XCTSkip("CGContext.makeImage failed on this host.")
        }
        return image
    }

    /// Polls a predicate up to `timeout` seconds, sleeping 25ms between
    /// checks. Returns whether the predicate became true.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ predicate: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return predicate()
    }

    // MARK: - Tests

    func testInitialState() {
        let viewModel = ScanViewModel()
        XCTAssertNil(viewModel.stage)
        XCTAssertNil(viewModel.result)
        XCTAssertNil(viewModel.failure)
        XCTAssertFalse(viewModel.isRunning)
    }

    func testIdentityHashableInequality() {
        let first = ScanViewModel()
        let second = ScanViewModel()
        XCTAssertEqual(first, first)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.hashValue, second.hashValue)
    }

    func testRunMarksRunningImmediately() throws {
        let cgImage = try makeCGImage()
        let viewModel = ScanViewModel()
        viewModel.run(
            cgImage: cgImage,
            layout: .auto,
            validatorPattern: #"^[A-Z]\d{5}$"#
        )
        // run() is synchronous up through setting isRunning; no await yet.
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertNil(viewModel.failure)
    }

    func testRunReachesTerminalState() async throws {
        let cgImage = try makeCGImage()
        let viewModel = ScanViewModel()
        viewModel.run(
            cgImage: cgImage,
            layout: .auto,
            validatorPattern: #"^[A-Z]\d{5}$"#
        )

        let finished = await waitUntil(timeout: 10) { !viewModel.isRunning }
        XCTAssertTrue(finished, "Pipeline did not finish within timeout.")

        // Either a successful empty-result happy path OR a Vision-context
        // failure on simulators where Vision can't initialize. Both are
        // acceptable terminal states for this test.
        if let failure = viewModel.failure {
            if case let .decodeFailed(underlying) = failure {
                let nsError = underlying as NSError
                if nsError.domain == "com.apple.Vision" && nsError.code == 9 {
                    throw XCTSkip("Vision inference context unavailable in this simulator.")
                }
            }
            // Any other failure is unexpected on a blank CGImage.
            XCTFail("Unexpected failure: \(failure)")
        } else {
            XCTAssertNotNil(viewModel.result, "Expected a ScanResult on success.")
            XCTAssertNil(viewModel.stage, "Stage should clear on completion.")
        }
    }

    func testReentrantRunCancelsPreviousAndAdvances() async throws {
        let cgImage = try makeCGImage()
        let viewModel = ScanViewModel()

        viewModel.run(
            cgImage: cgImage,
            layout: .auto,
            validatorPattern: #"^[A-Z]\d{5}$"#
        )
        // Immediately re-run before the first call could finish.
        viewModel.run(
            cgImage: cgImage,
            layout: .fixed(rows: 2, cols: 2),
            validatorPattern: #"^[A-Z]\d{5}$"#
        )

        XCTAssertTrue(viewModel.isRunning)
        let finished = await waitUntil(timeout: 10) { !viewModel.isRunning }
        XCTAssertTrue(finished, "Re-entrant run did not finish within timeout.")

        // Tolerate Vision-unavailable simulators.
        if let failure = viewModel.failure,
           case let .decodeFailed(underlying) = failure {
            let nsError = underlying as NSError
            if nsError.domain == "com.apple.Vision" && nsError.code == 9 {
                throw XCTSkip("Vision inference context unavailable in this simulator.")
            }
        }
        // On success, the final result reflects the second call's
        // fixed(2,2) layout — 4 cells.
        if let result = viewModel.result {
            XCTAssertEqual(result.layoutMode, .fixed(rows: 2, cols: 2))
            XCTAssertEqual(result.cells.count, 4)
        }
    }
}
