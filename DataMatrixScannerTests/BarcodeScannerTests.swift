import CoreGraphics
import XCTest
@testable import DataMatrixScanner

final class BarcodeScannerTests: XCTestCase {
    // MARK: - Helpers

    /// Generates a 1×1 transparent CGImage. Vision should return zero
    /// observations and zero errors.
    private func makeBlankCGImage(width: Int = 64, height: Int = 64) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw XCTSkip("Could not allocate CGContext on this host.")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw XCTSkip("CGContext.makeImage failed on this host.")
        }
        return image
    }

    /// Loads a Data Matrix fixture image from the test bundle.
    /// Returns `nil` if no fixture is present — fixture work is
    /// tracked as a follow-up to dms-yt9.
    private func loadDataMatrixFixture() -> CGImage? {
        // TODO(dms-yt9 follow-up): bundle a known-good Data Matrix PNG
        // (payload `A00011`) under DataMatrixScannerTests/Fixtures/ and
        // wire it into project.yml resources, then load it here.
        let bundle = Bundle(for: BarcodeScannerTests.self)
        guard let url = bundle.url(forResource: "datamatrix_A00011", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { return nil }
        return image
    }

    // MARK: - Tests

    /// Runs `scanner.scan` and skips the test if Vision raises the
    /// simulator-only "Could not create inference context" error
    /// (Vision domain code 9). Real devices and newer simulator builds
    /// don't hit this path.
    private func scanOrSkip(_ scanner: BarcodeScanner, image: CGImage) async throws -> [DetectedCode] {
        do {
            return try await scanner.scan(cgImage: image)
        } catch ScanError.decodeFailed(let underlying) {
            let nsError = underlying as NSError
            if nsError.domain == "com.apple.Vision" && nsError.code == 9 {
                throw XCTSkip("Vision inference context unavailable in this simulator (\(nsError.localizedDescription)).")
            }
            throw underlying
        }
    }

    func test_scan_blankImage_returnsEmptyArray() async throws {
        let scanner = BarcodeScanner()
        let image = try makeBlankCGImage()
        let codes = try await scanOrSkip(scanner, image: image)
        XCTAssertEqual(codes, [], "Blank image must yield zero detections (and not throw).")
    }

    func test_scan_emptyResults_isNotAnError() async throws {
        let scanner = BarcodeScanner()
        let image = try makeBlankCGImage(width: 128, height: 128)
        // Asserting no-throw is the contract: empty results are not an error.
        _ = try await scanOrSkip(scanner, image: image)
    }

    func test_scan_dataMatrixFixture_decodesPayload() async throws {
        guard let image = loadDataMatrixFixture() else {
            throw XCTSkip("v1.0: needs a generated Data Matrix fixture — tracked in dms-yt9 follow-up")
        }
        let scanner = BarcodeScanner()
        let codes = try await scanOrSkip(scanner, image: image)
        XCTAssertEqual(codes.count, 1, "Fixture should decode to exactly one code.")
        XCTAssertEqual(codes.first?.payload, "A00011")
    }

    func test_scan_dataMatrixFixture_boundingBoxIsNormalisedTopLeft() async throws {
        guard let image = loadDataMatrixFixture() else {
            throw XCTSkip("v1.0: needs a generated Data Matrix fixture — tracked in dms-yt9 follow-up")
        }
        let scanner = BarcodeScanner()
        let codes = try await scanOrSkip(scanner, image: image)
        guard let code = codes.first else {
            return XCTFail("Expected at least one detection from fixture.")
        }
        let box = code.boundingBox
        XCTAssertGreaterThanOrEqual(box.minX, 0)
        XCTAssertGreaterThanOrEqual(box.minY, 0)
        XCTAssertLessThanOrEqual(box.maxX, 1)
        XCTAssertLessThanOrEqual(box.maxY, 1)
        XCTAssertGreaterThan(box.width, 0)
        XCTAssertGreaterThan(box.height, 0)
        // Centroid should be inside the bbox.
        XCTAssertEqual(code.centroid.x, box.midX, accuracy: 1e-6)
        XCTAssertEqual(code.centroid.y, box.midY, accuracy: 1e-6)
    }

    func test_scan_dataMatrixFixture_confidenceInUnitRange() async throws {
        guard let image = loadDataMatrixFixture() else {
            throw XCTSkip("v1.0: needs a generated Data Matrix fixture — tracked in dms-yt9 follow-up")
        }
        let scanner = BarcodeScanner()
        let codes = try await scanOrSkip(scanner, image: image)
        for code in codes {
            XCTAssertGreaterThanOrEqual(code.confidence, 0)
            XCTAssertLessThanOrEqual(code.confidence, 1)
        }
    }
}
