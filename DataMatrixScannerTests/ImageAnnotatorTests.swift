import XCTest
import UIKit
@testable import DataMatrixScanner

final class ImageAnnotatorTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a solid-color test image at the given size and scale.
    private func makeImage(
        size: CGSize = CGSize(width: 200, height: 200),
        scale: CGFloat = 2,
        color: UIColor = .gray
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeDecodedCell(
        row: Int = 1,
        col: Int = 1,
        payload: String = "A00011",
        bbox: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        userOverride: String? = nil,
        userAdded: Bool = false
    ) -> GridCell {
        let code = DetectedCode(
            payload: payload,
            boundingBox: bbox,
            confidence: 0.95,
            rawBytes: nil
        )
        return GridCell(
            row: row,
            col: col,
            status: .decoded(code),
            userOverride: userOverride,
            userAdded: userAdded
        )
    }

    // MARK: - Tests

    /// Output preserves the input image's size exactly.
    func test_annotate_preservesImageSize() {
        let annotator = ImageAnnotator()
        let input = makeImage(size: CGSize(width: 320, height: 480))
        let cells = [makeDecodedCell()]

        let output = annotator.annotate(image: input, cells: cells)

        XCTAssertEqual(output.size, input.size)
    }

    /// Output preserves the input image's `scale`.
    func test_annotate_preservesImageScale() {
        let annotator = ImageAnnotator()
        let input = makeImage(scale: 3)
        let cells = [makeDecodedCell()]

        let output = annotator.annotate(image: input, cells: cells)

        XCTAssertEqual(output.scale, input.scale, accuracy: 0.001)
    }

    /// Empty cell list is a no-op: the input image is returned unchanged.
    func test_annotate_withEmptyCells_returnsInputUnchanged() {
        let annotator = ImageAnnotator()
        let input = makeImage()

        let output = annotator.annotate(image: input, cells: [])

        // Identity equality on UIImage instance — empty path returns the
        // original reference, no re-encode.
        XCTAssertTrue(output === input)
    }

    /// Drawing a `.decoded` cell mutates the rendered output (proves
    /// *something* was drawn beyond the source image).
    func test_annotate_withDecodedCell_changesPixelData() throws {
        let annotator = ImageAnnotator()
        let input = makeImage(color: .gray)

        // Re-render the input through the same path with no overlays so we
        // compare apples-to-apples (raw input vs annotated, both via the
        // renderer pipeline). The two should differ once a cell is drawn.
        let baseline = annotator.annotate(image: input, cells: [])
        let annotated = annotator.annotate(image: input, cells: [makeDecodedCell()])

        let baselineData = try XCTUnwrap(baseline.pngData())
        let annotatedData = try XCTUnwrap(annotated.pngData())

        XCTAssertNotEqual(baselineData, annotatedData)
    }

    /// `.empty` cells (which have no bounding box in v1.0) and `.unreadable`
    /// cells whose bbox is `nil` must be skipped without crashing.
    func test_annotate_skipsCellsWithoutBoundingBox() {
        let annotator = ImageAnnotator()
        let input = makeImage()

        let cells: [GridCell] = [
            GridCell(row: 1, col: 1, status: .empty),
            GridCell(
                row: 1, col: 2,
                status: .unreadable(reason: .decodeFailed, boundingBox: nil)
            )
        ]

        // Should not crash and should still return a valid image.
        let output = annotator.annotate(image: input, cells: cells)
        XCTAssertEqual(output.size, input.size)
    }

    /// `.unreadable` cells with a bounding box render an overlay (orange
    /// stroke + reason label).
    func test_annotate_unreadableCell_drawsOverlay() throws {
        let annotator = ImageAnnotator()
        let input = makeImage()

        let baseline = annotator.annotate(image: input, cells: [])

        let unreadable = GridCell(
            row: 1, col: 1,
            status: .unreadable(
                reason: .validatorRejected(decodedPayload: "AOO011"),
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
            )
        )
        let annotated = annotator.annotate(image: input, cells: [unreadable])

        let baselineData = try XCTUnwrap(baseline.pngData())
        let annotatedData = try XCTUnwrap(annotated.pngData())

        XCTAssertNotEqual(baselineData, annotatedData)
    }

    /// Outlier cells (row=-1, col=-1 with decoded status) render an overlay.
    func test_annotate_outlierCell_drawsOverlay() throws {
        let annotator = ImageAnnotator()
        let input = makeImage()

        let baseline = annotator.annotate(image: input, cells: [])

        let outlier = makeDecodedCell(
            row: -1,
            col: -1,
            payload: "Z99999",
            bbox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        )
        XCTAssertTrue(outlier.isOutlier)

        let annotated = annotator.annotate(image: input, cells: [outlier])

        let baselineData = try XCTUnwrap(baseline.pngData())
        let annotatedData = try XCTUnwrap(annotated.pngData())

        XCTAssertNotEqual(baselineData, annotatedData)
    }

    /// A decoded cell with a `userOverride` still renders (label switches
    /// to the override value, color switches to blue).
    func test_annotate_userOverriddenCell_drawsOverlay() throws {
        let annotator = ImageAnnotator()
        let input = makeImage()

        let baseline = annotator.annotate(image: input, cells: [])
        let edited = makeDecodedCell(payload: "A00011", userOverride: "B00042")
        let annotated = annotator.annotate(image: input, cells: [edited])

        let baselineData = try XCTUnwrap(baseline.pngData())
        let annotatedData = try XCTUnwrap(annotated.pngData())

        XCTAssertNotEqual(baselineData, annotatedData)
    }

    /// Bounding boxes anchored near the top edge fall back to placing the
    /// label below the bbox without crashing or overflowing.
    func test_annotate_topEdgeBoundingBox_doesNotCrash() {
        let annotator = ImageAnnotator()
        let input = makeImage()

        // bbox flush against the top edge — no room for a label above.
        let cell = makeDecodedCell(
            bbox: CGRect(x: 0.1, y: 0.0, width: 0.2, height: 0.1)
        )
        let output = annotator.annotate(image: input, cells: [cell])
        XCTAssertEqual(output.size, input.size)
    }
}
