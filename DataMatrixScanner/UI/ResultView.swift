import SwiftUI
import UIKit

/// v1.0 result screen — image (annotated when available, source while
/// the bake is in flight) plus the scrollable monospace CSV plus
/// Copy / Share buttons.
///
/// GridView, cell editor, recommendation surfaces, unplaced strip, and
/// the save-state machine land in dms-7ov (v1.1+). This view is
/// deliberately minimal so the v1.0 cut ships clean.
///
/// Lifecycle: `viewModel` is owned by the parent `ScanView` (it lives
/// on the navigation path). `ResultView` observes it via
/// `@ObservedObject` — never `@StateObject`.
public struct ResultView: View {

    @ObservedObject public var viewModel: ScanViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showCopyConfirmation: Bool = false
    @State private var shareItems: [Any]?
    @State private var isSharePresented: Bool = false

    /// Creates a result view bound to the supplied view-model.
    ///
    /// - Parameter viewModel: The pipeline-driven view-model owned by
    ///   the parent navigation stack.
    public init(viewModel: ScanViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let failure = viewModel.failure {
                failureView(failure)
            } else {
                contentView
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isSharePresented) {
            if let items = shareItems {
                ActivityShareSheet(activityItems: items)
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageSection
                if let result = viewModel.result {
                    statusRow(for: result)
                }
                csvSection
                actionRow
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        if let image = viewModel.result?.annotatedImage ?? viewModel.result?.sourceImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Scanned image")
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(Self.friendlyStageLabel(viewModel.stage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func statusRow(for result: ScanResult) -> some View {
        let decoded = result.cells.reduce(into: 0) { acc, cell in
            if case .decoded = cell.status { acc += 1 }
        }
        let unplaced = result.unplaced.count
        return Text("\(decoded) codes • \(unplaced) unplaced")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var csvSection: some View {
        let csv = viewModel.result?.csv ?? ""
        VStack(alignment: .leading, spacing: 6) {
            Text("CSV")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(csv.isEmpty ? "—" : csv)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 280)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        let hasResult = viewModel.result != nil
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    copyCSV()
                } label: {
                    Label("Copy CSV", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!hasResult)

                Button {
                    presentShareSheet()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasResult)
            }
            if showCopyConfirmation {
                Text("Copied!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func failureView(_ failure: ScanError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Scan failed")
                .font(.title3.weight(.semibold))
            Text(Self.failureMessage(for: failure))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func copyCSV() {
        guard let csv = viewModel.result?.csv else { return }
        UIPasteboard.general.string = csv
        withAnimation { showCopyConfirmation = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation { showCopyConfirmation = false }
            }
        }
    }

    private func presentShareSheet() {
        guard let result = viewModel.result else { return }
        let filename = CSVExporter.filename(for: result.timestamp)
        do {
            let url = try Self.writeCSVToTempFile(result.csv, filename: filename)
            shareItems = [url]
            isSharePresented = true
        } catch {
            shareItems = [result.csv]
            isSharePresented = true
        }
    }

    // MARK: - Testable helpers

    /// Maps a `PipelineStage` (or `nil`) to a user-facing progress
    /// label for the loading state of the result screen.
    public static func friendlyStageLabel(_ stage: PipelineStage?) -> String {
        guard let stage else { return "Working…" }
        switch stage {
        case .analyzingQuality: return "Analyzing quality…"
        case .decoding: return "Decoding…"
        case .validating: return "Validating…"
        case .inferringGrid: return "Inferring grid…"
        case .annotating: return "Annotating…"
        case .exporting: return "Exporting…"
        case .saving: return "Saving…"
        }
    }

    /// Maps a terminal `ScanError` to a user-facing message.
    public static func failureMessage(for error: ScanError) -> String {
        switch error {
        case .permissionDenied:
            return "Permission was denied. Grant access to continue."
        case .imageTooLarge:
            return "The selected image is too large to process."
        case .decodeFailed(let underlying):
            return "Decoding failed: \(underlying.localizedDescription)"
        }
    }

    /// Writes `csv` into the system temporary directory under
    /// `filename` (UTF-8) and returns the resulting `URL`.
    ///
    /// Used by the Share button so the receiving app sees a real
    /// `.csv` file with the canonical name rather than a raw string
    /// blob.
    public static func writeCSVToTempFile(_ csv: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
