import Foundation

/// Reason `ImageQualityAnalyzer` flagged the source image as poor.
public enum ImageQualityReason: Hashable, Codable, Sendable {
    case blur
    case underexposed
    case overexposed
}

/// A non-fatal warning surfaced to the user about the scan.
public enum QualityWarning: Hashable, Codable, Sendable {
    case lowDecodeRatio(decoded: Int, expected: Int)
    case codesRejectedByValidator(count: Int, examples: [String])
    case lowConfidenceReads(count: Int)
    case grossRotation(degrees: Double)
    case outliersDetected(count: Int)
    case imageQualityPoor(reason: ImageQualityReason)
}

/// Summary statistics and warnings produced by the pipeline.
public struct ScanQualityReport: Hashable, Codable, Sendable {
    public let decodedCount: Int
    public let rejectedByValidatorCount: Int
    /// Present in `.fixed` layout mode; `nil` in `.auto`.
    public let expectedCount: Int?
    public let outlierCount: Int
    /// Principal-axis angle in degrees from horizontal.
    public let principalAxisAngle: Double
    /// Lowest decoder confidence among accepted cells.
    public let confidenceFloor: Float
    public let warnings: [QualityWarning]

    public init(
        decodedCount: Int,
        rejectedByValidatorCount: Int,
        expectedCount: Int?,
        outlierCount: Int,
        principalAxisAngle: Double,
        confidenceFloor: Float,
        warnings: [QualityWarning]
    ) {
        self.decodedCount = decodedCount
        self.rejectedByValidatorCount = rejectedByValidatorCount
        self.expectedCount = expectedCount
        self.outlierCount = outlierCount
        self.principalAxisAngle = principalAxisAngle
        self.confidenceFloor = confidenceFloor
        self.warnings = warnings
    }
}
