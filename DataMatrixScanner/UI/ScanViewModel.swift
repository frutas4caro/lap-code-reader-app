import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// View-model that owns a single scan-pipeline run and exposes its
/// streaming state to SwiftUI as `@Published` properties.
///
/// The view-model is reference-typed (so SwiftUI navigation can route
/// on identity) and `Identifiable`/`Hashable` keyed off a stable `UUID`
/// so it can be used as a `NavigationStack` path element. Equality is
/// identity equality — two distinct instances are never equal even if
/// they end up with the same result.
///
/// Re-entrancy: calling `run(...)` while a previous run is still in
/// flight cancels the prior task before kicking off the new one. This
/// keeps the UI predictable when the user picks a new photo before the
/// last one finishes.
///
/// Threading: every published mutation happens on the main actor.
@MainActor
public final class ScanViewModel: ObservableObject, Identifiable, Hashable {

    /// Stable identifier — drives `Identifiable` and `Hashable`. New
    /// `ScanViewModel` instances always get a fresh `UUID`, so two
    /// distinct view-models are never equal.
    public let id: UUID

    /// The current pipeline stage label, or `nil` when no run is in
    /// progress (or the run has completed/failed).
    @Published public private(set) var stage: PipelineStage?

    /// Latest `ScanResult` emitted by the pipeline. Set on `.partial`
    /// and refreshed on `.complete`; `annotatedImage` is updated
    /// in-place when `.annotated` arrives.
    @Published public private(set) var result: ScanResult?

    /// Terminal failure from the pipeline, if any.
    @Published public private(set) var failure: ScanError?

    /// `true` between the call to `run(...)` and the stream's
    /// completion (success or failure).
    @Published public private(set) var isRunning: Bool

    private var consumer: Task<Void, Never>?

    /// Creates an idle view-model. Call `run(...)` to start a scan.
    public init() {
        self.id = UUID()
        self.stage = nil
        self.result = nil
        self.failure = nil
        self.isRunning = false
    }

    /// Kicks off a new pipeline run against `cgImage`. Cancels any
    /// in-flight run first so only the most recent invocation drives
    /// the published state.
    ///
    /// - Parameters:
    ///   - cgImage: Source image. `CGImage` is `Sendable` so it
    ///     crosses the actor boundary cleanly.
    ///   - layout: Layout mode to pass to `ScanPipeline`.
    ///   - validatorPattern: Regex captured into `ScanResult` and used
    ///     to instantiate the per-run `PayloadValidator`.
    public func run(
        cgImage: CGImage,
        layout: BoxLayout,
        validatorPattern: String
    ) {
        consumer?.cancel()
        stage = nil
        result = nil
        failure = nil
        isRunning = true

        consumer = Task { [weak self] in
            let pipeline = ScanPipeline()
            let stream = await pipeline.run(
                cgImage: cgImage,
                layout: layout,
                validatorPattern: validatorPattern
            )
            for await event in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                await self.handle(event: event)
            }
            if Task.isCancelled { return }
            await self?.markFinishedIfStillRunning()
        }
    }

    private func handle(event: PipelineEvent) {
        switch event {
        case let .stage(stage):
            self.stage = stage
        case let .partial(result):
            self.result = result
        case let .annotated(image):
            self.result?.annotatedImage = image
        case let .complete(result):
            self.result = result
            self.stage = nil
            self.isRunning = false
        case let .failed(error):
            self.failure = error
            self.stage = nil
            self.isRunning = false
        }
    }

    private func markFinishedIfStillRunning() {
        if isRunning {
            isRunning = false
            stage = nil
        }
    }

    // MARK: - Hashable / Equatable

    public static func == (lhs: ScanViewModel, rhs: ScanViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
