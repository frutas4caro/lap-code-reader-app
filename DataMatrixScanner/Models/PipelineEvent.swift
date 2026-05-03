import Foundation
import UIKit

/// Progress label for the pipeline's current stage.
public enum PipelineStage: Hashable, Sendable {
    case analyzingQuality
    case decoding
    case validating
    case inferringGrid
    case annotating
    case exporting
    case saving
}

/// Streaming event produced by `ScanPipeline.run(...)`.
///
/// `partial` emits as soon as cells are ready (~700ms target on a
/// 100-code image) so the UI can render and accept edits before the
/// initial annotation bake completes. `failed` is terminal.
public enum PipelineEvent: Sendable {
    case stage(PipelineStage)
    case partial(ScanResult)
    case annotated(UIImage)
    case complete(ScanResult)
    case failed(ScanError)
}
