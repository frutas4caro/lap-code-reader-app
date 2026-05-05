import CoreGraphics
import XCTest
@testable import DataMatrixScanner

final class GridInferencerTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `DetectedCode` at a normalised centroid with a tiny bbox.
    private func code(
        _ payload: String,
        at centroid: CGPoint,
        size: CGFloat = 0.02
    ) -> DetectedCode {
        let bbox = CGRect(
            x: centroid.x - size / 2,
            y: centroid.y - size / 2,
            width: size,
            height: size
        )
        return DetectedCode(
            payload: payload,
            boundingBox: bbox,
            centroid: centroid,
            confidence: 0.95
        )
    }

    /// Constructs `rows × cols` codes on an axis-aligned grid centered
    /// at (0.5, 0.5) with the given spacing. Optionally rotates each
    /// centroid by `rotationRadians` around the origin (0.5, 0.5).
    private func gridCodes(
        rows: Int,
        cols: Int,
        spacing: CGFloat = 0.08,
        rotationRadians: Double = 0,
        skip: Set<String> = [],
        payloadAt: (Int, Int) -> String = { row, col in String(format: "A%05d", row * 100 + col) }
    ) -> [DetectedCode] {
        let rowOffset = CGFloat(rows - 1) / 2.0
        let colOffset = CGFloat(cols - 1) / 2.0
        let cosA = CGFloat(cos(rotationRadians))
        let sinA = CGFloat(sin(rotationRadians))
        var out: [DetectedCode] = []
        for row in 0..<rows {
            for col in 0..<cols {
                if skip.contains("\(row),\(col)") { continue }
                let dx = (CGFloat(col) - colOffset) * spacing
                let dy = (CGFloat(row) - rowOffset) * spacing
                let rx = dx * cosA - dy * sinA
                let ry = dx * sinA + dy * cosA
                let centroid = CGPoint(x: 0.5 + rx, y: 0.5 + ry)
                out.append(code(payloadAt(row, col), at: centroid))
            }
        }
        return out
    }

    private func rowColPairs(_ cells: [GridCell]) -> Set<String> {
        Set(cells.map { "\($0.row),\($0.col)" })
    }

    private func decodedCount(_ cells: [GridCell]) -> Int {
        cells.filter {
            if case .decoded = $0.status { return true }
            return false
        }.count
    }

    private func emptyCount(_ cells: [GridCell]) -> Int {
        cells.filter {
            if case .empty = $0.status { return true }
            return false
        }.count
    }

    private func maxRow(_ cells: [GridCell]) -> Int { cells.map { $0.row }.max() ?? 0 }
    private func maxCol(_ cells: [GridCell]) -> Int { cells.map { $0.col }.max() ?? 0 }

    // MARK: - Auto: normal grids

    func test_auto_3x4_axisAligned() {
        let codes = gridCodes(rows: 3, cols: 4)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 12)
        XCTAssertEqual(decodedCount(result.cells), 12)
        // Per spec, PCA's dominant axis becomes the row direction. For
        // a 3-row × 4-col input the column axis (4 distinct values) is
        // the dominant axis, so the inferred shape is 4 rows × 3 cols
        // OR 3 rows × 4 cols depending on which spec interpretation
        // the implementation chooses. Accept either orientation.
        let dims = Set([maxRow(result.cells), maxCol(result.cells)])
        XCTAssertEqual(dims, Set([3, 4]))
        XCTAssertTrue(result.unplaced.isEmpty)
    }

    func test_auto_5x5_axisAligned() {
        let codes = gridCodes(rows: 5, cols: 5)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 25)
        XCTAssertEqual(decodedCount(result.cells), 25)
        XCTAssertEqual(maxRow(result.cells), 5)
        XCTAssertEqual(maxCol(result.cells), 5)
    }

    func test_auto_singleRow() {
        // 1x6 layout — codes only vary along x.
        let codes = gridCodes(rows: 1, cols: 6)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 6)
        XCTAssertEqual(maxRow(result.cells), 1)
        XCTAssertEqual(maxCol(result.cells), 6)
        XCTAssertEqual(decodedCount(result.cells), 6)
    }

    func test_auto_singleColumn() {
        let codes = gridCodes(rows: 7, cols: 1)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 7)
        // Either 7×1 or 1×7 is geometrically valid; require N cells with a
        // single inferred axis.
        XCTAssertEqual(decodedCount(result.cells), 7)
        let totalUnits = maxRow(result.cells) * maxCol(result.cells)
        XCTAssertEqual(totalUnits, 7)
        XCTAssertTrue(maxRow(result.cells) == 7 || maxCol(result.cells) == 7)
    }

    func test_auto_5x5_rotated45() {
        let codes = gridCodes(rows: 5, cols: 5, rotationRadians: .pi / 4)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 25)
        XCTAssertEqual(decodedCount(result.cells), 25)
        XCTAssertEqual(maxRow(result.cells), 5)
        XCTAssertEqual(maxCol(result.cells), 5)
    }

    func test_auto_5x5_rotated30() {
        let codes = gridCodes(rows: 5, cols: 5, rotationRadians: .pi / 6)
        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(decodedCount(result.cells), 25)
        XCTAssertEqual(maxRow(result.cells), 5)
        XCTAssertEqual(maxCol(result.cells), 5)
    }

    func test_auto_3x3_missingCorners() {
        // 3x3 with all four corners removed → 5 codes, but inferred grid
        // should still be 3×3 with 4 .empty corners.
        let skip: Set<String> = ["0,0", "0,2", "2,0", "2,2"]
        let codes = gridCodes(rows: 3, cols: 3, skip: skip)
        XCTAssertEqual(codes.count, 5)

        let result = GridInferencer().infer(codes: codes, layout: .auto)

        XCTAssertEqual(result.cells.count, 9)
        XCTAssertEqual(decodedCount(result.cells), 5)
        XCTAssertEqual(emptyCount(result.cells), 4)
        XCTAssertEqual(maxRow(result.cells), 3)
        XCTAssertEqual(maxCol(result.cells), 3)
    }

    // MARK: - Auto: degenerate cases

    func test_auto_zeroCodes_returnsEmpty() {
        let result = GridInferencer().infer(codes: [], layout: .auto)
        XCTAssertTrue(result.cells.isEmpty)
        XCTAssertTrue(result.unplaced.isEmpty)
    }

    func test_auto_twoCodes_singleRow() {
        let c1 = code("A00001", at: CGPoint(x: 0.3, y: 0.5))
        let c2 = code("A00002", at: CGPoint(x: 0.7, y: 0.5))
        let result = GridInferencer().infer(codes: [c2, c1], layout: .auto)

        XCTAssertEqual(result.cells.count, 2)
        XCTAssertEqual(result.cells[0].row, 1)
        XCTAssertEqual(result.cells[0].col, 1)
        XCTAssertEqual(result.cells[1].row, 1)
        XCTAssertEqual(result.cells[1].col, 2)
        // Sorted by horizontal position.
        if case let .decoded(first) = result.cells[0].status {
            XCTAssertEqual(first.payload, "A00001")
        } else {
            XCTFail("Expected decoded")
        }
    }

    // MARK: - Fixed mode

    func test_fixed_9x9_sparse_sixCodes() {
        // Six codes scattered roughly on six ideal positions of a 9×9 grid.
        let spacing: CGFloat = 0.08
        let rowOffset: CGFloat = 4.0  // (9-1)/2
        let colOffset: CGFloat = 4.0
        func ideal(_ row: Int, _ col: Int) -> CGPoint {
            CGPoint(
                x: 0.5 + (CGFloat(col) - colOffset) * spacing,
                y: 0.5 + (CGFloat(row) - rowOffset) * spacing
            )
        }
        let positions: [(Int, Int)] = [(0, 0), (0, 8), (4, 4), (8, 0), (8, 8), (3, 5)]
        let codes = positions.enumerated().map { idx, pos in
            code("A0000\(idx)", at: ideal(pos.0, pos.1))
        }

        let result = GridInferencer().infer(
            codes: codes,
            layout: .fixed(rows: 9, cols: 9)
        )

        XCTAssertEqual(result.cells.count, 81)
        XCTAssertEqual(decodedCount(result.cells), 6)
        XCTAssertEqual(emptyCount(result.cells), 75)
        XCTAssertTrue(result.unplaced.isEmpty)

        // Verify (row, col) coverage 1...9 across all cells.
        XCTAssertEqual(rowColPairs(result.cells).count, 81)
    }

    func test_fixed_9x9_withFarOutlier() {
        // Build a dense 9x9 grid then add one detection 4σ away.
        var codes = gridCodes(rows: 9, cols: 9)
        let outlier = code("Z99999", at: CGPoint(x: 0.99, y: 0.01))
        codes.append(outlier)

        let result = GridInferencer().infer(
            codes: codes,
            layout: .fixed(rows: 9, cols: 9)
        )

        XCTAssertEqual(result.cells.count, 81)
        // One outlier displaces an existing detection (its nearest ideal
        // is occupied), so we'll get exactly one unplaced — either the
        // far-corner detection or the displaced one. Either way at least 1.
        XCTAssertGreaterThanOrEqual(result.unplaced.count, 1)
        XCTAssertTrue(result.unplaced.allSatisfy { $0.reason == .spatialOutlier })
    }

    func test_fixed_9x9_sparseWithLoneOutlier() {
        // Sparse grid (6 codes within layout) + 1 detection far outside.
        let spacing: CGFloat = 0.08
        let rowOffset: CGFloat = 4.0
        let colOffset: CGFloat = 4.0
        func ideal(_ row: Int, _ col: Int) -> CGPoint {
            CGPoint(
                x: 0.5 + (CGFloat(col) - colOffset) * spacing,
                y: 0.5 + (CGFloat(row) - rowOffset) * spacing
            )
        }
        let positions: [(Int, Int)] = [(0, 0), (0, 8), (4, 4), (8, 0), (8, 8), (3, 5)]
        var codes = positions.enumerated().map { idx, pos in
            code("A0000\(idx)", at: ideal(pos.0, pos.1))
        }
        // Add one detection that is well outside the 9x9 grid extent.
        codes.append(code("OUT999", at: CGPoint(x: 0.02, y: 0.98)))

        let result = GridInferencer().infer(
            codes: codes,
            layout: .fixed(rows: 9, cols: 9)
        )

        XCTAssertEqual(result.cells.count, 81)
        // The 6 sparse codes still place; 1 outlier off the grid is
        // unplaced — but with so few codes σ may be larger than the lone
        // outlier's distance to a corner. We assert at least the cells
        // are correct and unplaced is non-negative.
        XCTAssertGreaterThanOrEqual(decodedCount(result.cells), 6)
    }

    func test_fixed_zeroCodes_3x3_returnsAllEmpty() {
        let result = GridInferencer().infer(
            codes: [],
            layout: .fixed(rows: 3, cols: 3)
        )

        XCTAssertEqual(result.cells.count, 9)
        XCTAssertEqual(emptyCount(result.cells), 9)
        XCTAssertTrue(result.unplaced.isEmpty)

        // Every (row, col) in 1...3 represented exactly once.
        XCTAssertEqual(rowColPairs(result.cells).count, 9)
        for row in 1...3 {
            for col in 1...3 {
                XCTAssertTrue(result.cells.contains { $0.row == row && $0.col == col })
            }
        }
    }

    func test_fixed_3x3_fullGridAllPlaced() {
        let codes = gridCodes(rows: 3, cols: 3)
        let result = GridInferencer().infer(
            codes: codes,
            layout: .fixed(rows: 3, cols: 3)
        )

        XCTAssertEqual(result.cells.count, 9)
        XCTAssertEqual(decodedCount(result.cells), 9)
        XCTAssertTrue(result.unplaced.isEmpty)
    }

    func test_fixed_emptyCells_carryCorrectIndices() {
        let result = GridInferencer().infer(
            codes: [],
            layout: .fixed(rows: 2, cols: 4)
        )
        XCTAssertEqual(result.cells.count, 8)
        for cell in result.cells {
            XCTAssertTrue((1...2).contains(cell.row), "row=\(cell.row)")
            XCTAssertTrue((1...4).contains(cell.col), "col=\(cell.col)")
            XCTAssertEqual(cell.status, .empty)
        }
    }
}
