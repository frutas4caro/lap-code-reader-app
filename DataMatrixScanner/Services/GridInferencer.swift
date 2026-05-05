// swiftlint:disable file_length
//
// Grid inference is inherently a long algorithm — the public surface is
// tiny but the geometry math (PCA, clustering, ICP refinement) demands
// a body length / type length above the project default.

import CoreGraphics
import Foundation

// swiftlint:disable type_body_length

/// Infers a `[GridCell]` (and `[UnplacedDetection]`) from raw
/// `DetectedCode` centroids.
///
/// Two layout modes are supported:
/// - `.auto` infers row and column counts from the centroid distribution
///   via PCA + 1D gap clustering.
/// - `.fixed(rows, cols)` constructs a `rows × cols` ideal grid at the
///   PCA-recovered orientation and maps each detection to its nearest
///   ideal position.
///
/// See `docs/grid-inference.md` for the full algorithm.
public struct GridInferencer: Sendable {

    /// Tunable parameters that mirror the user-facing Settings keys
    /// (`gapThresholdMultiplier`, `outlierSigmaThreshold`).
    public struct Tuning: Sendable {
        /// Multiplier applied to the median 1-D gap when auto-clustering
        /// rows or columns. Larger values collapse adjacent clusters.
        public let gapThresholdMultiplier: Double
        /// Standard-deviation multiplier above which a detection becomes
        /// a spatial outlier in `.fixed` mode.
        public let outlierSigmaThreshold: Double

        /// Creates a tuning instance with the documented v1 defaults.
        public init(
            gapThresholdMultiplier: Double = 1.5,
            outlierSigmaThreshold: Double = 3.0
        ) {
            self.gapThresholdMultiplier = gapThresholdMultiplier
            self.outlierSigmaThreshold = outlierSigmaThreshold
        }
    }

    /// One ideal-position slot in a `.fixed`-mode grid.
    private struct IdealSlot {
        let row: Int
        let col: Int
        let point: CGPoint
    }

    /// Eigen-decomposition result for the centroid covariance matrix.
    private struct AxisFrame {
        let axisU: CGPoint
        let axisV: CGPoint
        let lambda1: Double
        let lambda2: Double
    }

    private let tuning: Tuning

    /// Creates an inferencer with the supplied tuning parameters.
    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Infers grid cells (and any unplaced detections) for the given
    /// detections under the supplied layout mode.
    ///
    /// In `.auto` mode `unplaced` is always empty: every detection
    /// becomes a `.decoded` cell at some inferred `(row, col)`. In
    /// `.fixed` mode, detections whose distance to the nearest ideal
    /// position exceeds `outlierSigmaThreshold × σ` are returned as
    /// `UnplacedDetection` with `.spatialOutlier`.
    public func infer(
        codes: [DetectedCode],
        layout: BoxLayout
    ) -> (cells: [GridCell], unplaced: [UnplacedDetection]) {
        switch layout {
        case .auto:
            return (inferAuto(codes: codes), [])
        case let .fixed(rows, cols):
            return inferFixed(codes: codes, rows: rows, cols: cols)
        }
    }

    // MARK: - Auto

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func inferAuto(codes: [DetectedCode]) -> [GridCell] {
        if codes.isEmpty {
            return []
        }

        // Per spec: <3 codes → skip PCA, assign sequentially as one row.
        if codes.count < 3 {
            let sorted = codes.sorted { $0.centroid.x < $1.centroid.x }
            return sorted.enumerated().map { idx, code in
                GridCell(row: 1, col: idx + 1, status: .decoded(code))
            }
        }

        // Compute principal axes.
        let centroids = codes.map { $0.centroid }
        let mean = meanPoint(centroids)
        let pcaResult = principalAxes(of: centroids, mean: mean)
        var axisU = pcaResult.axisU
        var axisV = pcaResult.axisV

        // Near-isotropic eigenvalues (e.g. square grid) → PCA cannot
        // disambiguate orientation. Search candidate rotations and
        // pick the one whose `(rowClusters × colClusters)` product is
        // ≥ codes.count and minimises the overshoot.
        let isotropy = pcaResult.lambda2 / max(pcaResult.lambda1, 1e-12)
        if isotropy > 0.9 {
            let originalU = axisU
            let total = codes.count
            let candidates = stride(from: 0.0, to: .pi / 2, by: .pi / 36).map { $0 }
            var bestScore = (overshoot: Int.max, product: Int.max)
            for angle in candidates {
                let cosA = cos(angle)
                let sinA = sin(angle)
                let candU = CGPoint(
                    x: CGFloat(Double(originalU.x) * cosA - Double(originalU.y) * sinA),
                    y: CGFloat(Double(originalU.x) * sinA + Double(originalU.y) * cosA)
                )
                let candV = CGPoint(x: -candU.y, y: candU.x)
                let testU = codes.map { project($0.centroid, mean: mean, axis: candU) }
                let testV = codes.map { project($0.centroid, mean: mean, axis: candV) }
                let clustU = clusterIndices(projections: testU, multiplier: tuning.gapThresholdMultiplier)
                let clustV = clusterIndices(projections: testV, multiplier: tuning.gapThresholdMultiplier)
                let rowsU = (clustU.max() ?? 0) + 1
                let colsV = (clustV.max() ?? 0) + 1
                let product = rowsU * colsV
                // Disqualify orientations that cannot accommodate every
                // detection — a perfect grid satisfies rows*cols ≥ N.
                let overshoot = product >= total ? product - total : Int.max
                let score = (overshoot: overshoot, product: product)
                if score < bestScore {
                    bestScore = score
                    axisU = candU
                    axisV = candV
                }
            }
        }

        // Project each centroid onto the two axes.
        let projU = codes.map { project($0.centroid, mean: mean, axis: axisU) }
        let projV = codes.map { project($0.centroid, mean: mean, axis: axisV) }

        // Detect single-row / single-column degeneracy: if one axis has
        // negligible spread relative to the other, treat all detections
        // as one cluster on that axis.
        let spreadU = (projU.max() ?? 0) - (projU.min() ?? 0)
        let spreadV = (projV.max() ?? 0) - (projV.min() ?? 0)
        let dominantSpread = max(spreadU, spreadV)
        let degenerateRatio = 0.05  // V spread <5% of U spread → 1 row

        let rowClusters: [Int]
        let colClusters: [Int]

        if dominantSpread > 0 && spreadV / dominantSpread < degenerateRatio {
            // All on one row; each unique projected value along U is
            // its own column.
            rowClusters = Array(repeating: 0, count: codes.count)
            colClusters = sequentialClusterIndices(projections: projU)
        } else if dominantSpread > 0 && spreadU / dominantSpread < degenerateRatio {
            // All in one column; each unique projected value along V
            // is its own row.
            colClusters = Array(repeating: 0, count: codes.count)
            rowClusters = sequentialClusterIndices(projections: projV)
        } else {
            rowClusters = clusterIndices(projections: projU, multiplier: tuning.gapThresholdMultiplier)
            colClusters = clusterIndices(projections: projV, multiplier: tuning.gapThresholdMultiplier)
        }

        let rowCount = (rowClusters.max() ?? 0) + 1
        let colCount = (colClusters.max() ?? 0) + 1

        // Build mapping: (row, col) → DetectedCode (latest wins on collision).
        var occupied: [String: DetectedCode] = [:]
        for (idx, code) in codes.enumerated() {
            let key = "\(rowClusters[idx])-\(colClusters[idx])"
            occupied[key] = code
        }

        var cells: [GridCell] = []
        cells.reserveCapacity(rowCount * colCount)
        for row in 0..<rowCount {
            for col in 0..<colCount {
                let key = "\(row)-\(col)"
                if let code = occupied[key] {
                    cells.append(GridCell(row: row + 1, col: col + 1, status: .decoded(code)))
                } else {
                    cells.append(GridCell(row: row + 1, col: col + 1, status: .empty))
                }
            }
        }
        return cells
    }

    // MARK: - Fixed

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func inferFixed(
        codes: [DetectedCode],
        rows: Int,
        cols: Int
    ) -> (cells: [GridCell], unplaced: [UnplacedDetection]) {
        // Empty → all empty cells, no unplaced.
        if codes.isEmpty {
            var cells: [GridCell] = []
            cells.reserveCapacity(rows * cols)
            for row in 1...rows {
                for col in 1...cols {
                    cells.append(GridCell(row: row, col: col, status: .empty))
                }
            }
            return (cells, [])
        }

        let centroids = codes.map { $0.centroid }
        let mean = meanPoint(centroids)

        // Recover orientation. With <3 codes use axis-aligned frame.
        let axisU: CGPoint
        let axisV: CGPoint
        if codes.count < 3 {
            axisU = CGPoint(x: 1, y: 0)
            axisV = CGPoint(x: 0, y: 1)
        } else {
            let frame = principalAxes(of: centroids, mean: mean)
            axisU = frame.axisU
            axisV = frame.axisV
        }

        // Spacing strategy: prefer the projection-spread estimate
        // (`spread / (dim - 1)`) since it remains accurate for sparse
        // grids whose detections span the layout. Fall back to the
        // nearest-neighbour median when the spread is zero (≤ 1 code
        // contributes meaningfully).
        let projU = codes.map { project($0.centroid, mean: mean, axis: axisU) }
        let projV = codes.map { project($0.centroid, mean: mean, axis: axisV) }
        let spreadU = (projU.max() ?? 0) - (projU.min() ?? 0)
        let spreadV = (projV.max() ?? 0) - (projV.min() ?? 0)
        let nnDistances = nearestNeighbourDistances(centroids)
        let medianNN = median(nnDistances) ?? 0

        let rowSpacing: Double
        if rows > 1 && spreadU > 0 {
            rowSpacing = spreadU / Double(rows - 1)
        } else if medianNN > 0 {
            rowSpacing = medianNN
        } else {
            rowSpacing = 1.0 / Double(max(rows, 1))
        }

        let colSpacing: Double
        if cols > 1 && spreadV > 0 {
            colSpacing = spreadV / Double(cols - 1)
        } else if medianNN > 0 {
            colSpacing = medianNN
        } else {
            colSpacing = 1.0 / Double(max(cols, 1))
        }

        let medianSpacingForSigma = max(min(rowSpacing, colSpacing), 1e-6)
        let sigma: Double
        if medianNN > 0 {
            sigma = max(stdDev(nnDistances, mean: medianNN), medianSpacingForSigma * 0.05)
        } else {
            sigma = medianSpacingForSigma * 0.25
        }

        // Build ideal grid + run a single ICP-style anchor refinement
        // so sparse grids whose centroid mean does not coincide with
        // the layout centre still place correctly.
        let initialAnchor = mean
        var idealPositions = buildIdealGrid(
            anchor: initialAnchor,
            rows: rows,
            cols: cols,
            rowSpacing: rowSpacing,
            colSpacing: colSpacing,
            axisU: axisU,
            axisV: axisV
        )
        var dxSum = 0.0
        var dySum = 0.0
        for code in codes {
            var bestDx = 0.0
            var bestDy = 0.0
            var bestDist = Double.infinity
            for pos in idealPositions {
                let dx = Double(code.centroid.x - pos.point.x)
                let dy = Double(code.centroid.y - pos.point.y)
                let dist2 = dx * dx + dy * dy
                if dist2 < bestDist {
                    bestDist = dist2
                    bestDx = dx
                    bestDy = dy
                }
            }
            dxSum += bestDx
            dySum += bestDy
        }
        let codeCount = Double(max(codes.count, 1))
        let refinedAnchor = CGPoint(
            x: initialAnchor.x + CGFloat(dxSum / codeCount),
            y: initialAnchor.y + CGFloat(dySum / codeCount)
        )
        idealPositions = buildIdealGrid(
            anchor: refinedAnchor,
            rows: rows,
            cols: cols,
            rowSpacing: rowSpacing,
            colSpacing: colSpacing,
            axisU: axisU,
            axisV: axisV
        )

        // For each detection, find nearest ideal slot.
        struct Candidate {
            let codeIndex: Int
            let posIndex: Int
            let distance: Double
        }
        var candidates: [Candidate] = []
        candidates.reserveCapacity(codes.count)

        let outlierThreshold = tuning.outlierSigmaThreshold * sigma

        var unplacedIndices: [Int] = []
        for (codeIdx, code) in codes.enumerated() {
            var bestIdx = -1
            var bestDist = Double.infinity
            for (posIdx, pos) in idealPositions.enumerated() {
                let dx = Double(code.centroid.x - pos.point.x)
                let dy = Double(code.centroid.y - pos.point.y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = posIdx
                }
            }
            if bestIdx >= 0 && bestDist <= outlierThreshold {
                candidates.append(Candidate(codeIndex: codeIdx, posIndex: bestIdx, distance: bestDist))
            } else {
                unplacedIndices.append(codeIdx)
            }
        }

        // Resolve collisions: closest candidate per ideal pos wins.
        var assignedCode: [Int: Int] = [:]
        var assignedDistance: [Int: Double] = [:]
        var displaced: [Int] = []
        for cand in candidates {
            if let existingDist = assignedDistance[cand.posIndex] {
                if cand.distance < existingDist {
                    if let prevCode = assignedCode[cand.posIndex] {
                        displaced.append(prevCode)
                    }
                    assignedCode[cand.posIndex] = cand.codeIndex
                    assignedDistance[cand.posIndex] = cand.distance
                } else {
                    displaced.append(cand.codeIndex)
                }
            } else {
                assignedCode[cand.posIndex] = cand.codeIndex
                assignedDistance[cand.posIndex] = cand.distance
            }
        }

        // Build cells.
        var cells: [GridCell] = []
        cells.reserveCapacity(rows * cols)
        for (posIdx, pos) in idealPositions.enumerated() {
            if let codeIdx = assignedCode[posIdx] {
                cells.append(GridCell(row: pos.row, col: pos.col, status: .decoded(codes[codeIdx])))
            } else {
                cells.append(GridCell(row: pos.row, col: pos.col, status: .empty))
            }
        }

        // Build unplaced.
        var unplaced: [UnplacedDetection] = []
        for idx in unplacedIndices + displaced {
            let code = codes[idx]
            unplaced.append(UnplacedDetection(
                payload: code.payload,
                boundingBox: code.boundingBox,
                confidence: code.confidence,
                reason: .spatialOutlier,
                rawBytes: code.rawBytes
            ))
        }

        return (cells, unplaced)
    }

    // swiftlint:disable:next function_parameter_count
    private func buildIdealGrid(
        anchor: CGPoint,
        rows: Int,
        cols: Int,
        rowSpacing: Double,
        colSpacing: Double,
        axisU: CGPoint,
        axisV: CGPoint
    ) -> [IdealSlot] {
        let rowOffset = Double(rows - 1) / 2.0
        let colOffset = Double(cols - 1) / 2.0
        var pts: [IdealSlot] = []
        pts.reserveCapacity(rows * cols)
        for row in 0..<rows {
            for col in 0..<cols {
                let dRow = (Double(row) - rowOffset) * rowSpacing
                let dCol = (Double(col) - colOffset) * colSpacing
                let px = Double(anchor.x) + dRow * Double(axisU.x) + dCol * Double(axisV.x)
                let py = Double(anchor.y) + dRow * Double(axisU.y) + dCol * Double(axisV.y)
                pts.append(IdealSlot(row: row + 1, col: col + 1, point: CGPoint(x: px, y: py)))
            }
        }
        return pts
    }

    // MARK: - Geometry helpers

    private func meanPoint(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let count = Double(pts.count)
        var sx = 0.0
        var sy = 0.0
        for pnt in pts {
            sx += Double(pnt.x)
            sy += Double(pnt.y)
        }
        return CGPoint(x: sx / count, y: sy / count)
    }

    /// Returns the unit principal axis frame (`axisU` largest
    /// eigenvalue, `axisV` orthogonal) and both eigenvalues so callers
    /// can detect near-isotropic point clouds. Closed-form 2x2
    /// eigenvector solution.
    private func principalAxes(of pts: [CGPoint], mean: CGPoint) -> AxisFrame {
        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for pnt in pts {
            let dx = Double(pnt.x - mean.x)
            let dy = Double(pnt.y - mean.y)
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        let denom = Double(max(pts.count - 1, 1))
        let cxx = sxx / denom
        let cyy = syy / denom
        let cxy = sxy / denom

        // Eigenvalues of [[cxx, cxy], [cxy, cyy]].
        let trace = cxx + cyy
        let det = cxx * cyy - cxy * cxy
        let disc = max(trace * trace / 4.0 - det, 0)
        let lambda1 = trace / 2.0 + disc.squareRoot()
        let lambda2 = trace / 2.0 - disc.squareRoot()
        // Eigenvector for lambda1: solve (cxx - lambda1) * x + cxy * y = 0.
        let ux: Double
        let uy: Double
        if abs(cxy) > 1e-12 {
            ux = lambda1 - cyy
            uy = cxy
        } else {
            // Diagonal covariance: pick the dominant axis.
            if cxx >= cyy {
                ux = 1
                uy = 0
            } else {
                ux = 0
                uy = 1
            }
        }
        let mag = (ux * ux + uy * uy).squareRoot()
        let nux = mag > 0 ? ux / mag : 1.0
        let nuy = mag > 0 ? uy / mag : 0.0
        let axisU = CGPoint(x: nux, y: nuy)
        let axisV = CGPoint(x: -nuy, y: nux)
        return AxisFrame(axisU: axisU, axisV: axisV, lambda1: lambda1, lambda2: lambda2)
    }

    private func project(_ pnt: CGPoint, mean: CGPoint, axis: CGPoint) -> Double {
        let dx = Double(pnt.x - mean.x)
        let dy = Double(pnt.y - mean.y)
        return dx * Double(axis.x) + dy * Double(axis.y)
    }

    /// Sorts the projections, computes consecutive gaps, splits where a
    /// gap exceeds `multiplier × median(gap)`. Returns a cluster index
    /// (0-based, ordered by ascending projection) for each input index.
    private func clusterIndices(projections: [Double], multiplier: Double) -> [Int] {
        let count = projections.count
        if count == 0 { return [] }
        if count == 1 { return [0] }

        // swiftlint:disable:next unused_enumerated
        let sortedWithIdx = projections.enumerated()
            .sorted { $0.element < $1.element }

        let sortedValues = sortedWithIdx.map { $0.element }
        var gaps: [Double] = []
        gaps.reserveCapacity(count - 1)
        for idx in 1..<count {
            gaps.append(sortedValues[idx] - sortedValues[idx - 1])
        }

        // Use the median of *all* gaps (zeros included) as the
        // within-cluster baseline. For perfectly-aligned synthetic
        // grids most gaps are 0 (codes share a projection value), so
        // the median is 0 and any positive gap becomes a split. For
        // noisy real data the median tracks the within-row jitter and
        // `multiplier × median` cleanly separates row jumps.
        let medianAll = median(gaps) ?? 0
        let threshold: Double
        if medianAll > 1e-12 {
            threshold = medianAll * multiplier
        } else {
            // All gaps are effectively zero except the genuine row/col
            // jumps; split on any positive gap.
            threshold = 1e-9
        }

        var clusterForSortedPos: [Int] = Array(repeating: 0, count: count)
        var current = 0
        for idx in 1..<count {
            if gaps[idx - 1] > threshold {
                current += 1
            }
            clusterForSortedPos[idx] = current
        }

        var result = Array(repeating: 0, count: count)
        for (sortedPos, entry) in sortedWithIdx.enumerated() {
            result[entry.offset] = clusterForSortedPos[sortedPos]
        }
        return result
    }

    /// Assigns each input projection a unique cluster index in
    /// ascending-projection order. Used for single-row / single-column
    /// degenerate cases where every detection is its own cluster on
    /// the dominant axis.
    private func sequentialClusterIndices(projections: [Double]) -> [Int] {
        let count = projections.count
        if count == 0 { return [] }
        // swiftlint:disable:next unused_enumerated
        let sortedWithIdx = projections.enumerated()
            .sorted { $0.element < $1.element }
        var result = Array(repeating: 0, count: count)
        for (sortedPos, entry) in sortedWithIdx.enumerated() {
            result[entry.offset] = sortedPos
        }
        return result
    }

    private func nearestNeighbourDistances(_ pts: [CGPoint]) -> [Double] {
        guard pts.count > 1 else { return [] }
        var result: [Double] = []
        result.reserveCapacity(pts.count)
        for idx in 0..<pts.count {
            var best = Double.infinity
            for jdx in 0..<pts.count where idx != jdx {
                let dx = Double(pts[idx].x - pts[jdx].x)
                let dy = Double(pts[idx].y - pts[jdx].y)
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < best { best = dist }
            }
            if best.isFinite {
                result.append(best)
            }
        }
        return result
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }

    private func stdDev(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        var sumSq = 0.0
        for val in values {
            let delta = val - mean
            sumSq += delta * delta
        }
        return (sumSq / Double(values.count - 1)).squareRoot()
    }
}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
