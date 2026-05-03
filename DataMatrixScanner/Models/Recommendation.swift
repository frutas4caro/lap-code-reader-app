import Foundation

/// User-facing action surfaced by `RemediationAdvisor`.
public enum RecommendationAction: Hashable, Sendable {
    case retakePhoto
    case enableTorch
    case manuallyEnterCode(row: Int, col: Int, prefill: String?)
    case relaxValidator(suggestedPattern: String?)
    case rotateGrid90
    case adjustGapThreshold
    case useAnyway
}

/// A user-facing recommendation produced by `RemediationAdvisor`.
public struct Recommendation: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let actions: [RecommendationAction]

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        actions: [RecommendationAction]
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actions = actions
    }
}
