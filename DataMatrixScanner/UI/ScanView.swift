import PhotosUI
import SwiftUI
import UIKit

/// Root view for v1.0. Presents a Photos picker as the single entry
/// point (camera capture lands in dms-6rn / v1.1). On selection the
/// view loads the chosen image, builds a `ScanViewModel`, kicks off
/// `ScanPipeline.run(...)`, and pushes the view-model onto the
/// navigation stack.
///
/// The destination is a placeholder — `ResultView` itself lands in
/// dms-hw2. The seam (`navigationDestination(for: ScanViewModel.self)`)
/// is the contract the next bead replaces.
public struct ScanView: View {

    @StateObject private var settings = AppSettings()
    @Environment(\.storageManager) private var storageManager
    @State private var path: [ScanViewModel] = []
    @State private var selectedItem: PhotosPickerItem?
    @State private var loadError: LoadError?

    /// Creates the root scan view.
    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 96))
                    .foregroundStyle(.tint)
                VStack(spacing: 8) {
                    Text("DataMatrix Grid Scanner")
                        .font(.title2.weight(.semibold))
                    Text("Pick a photo of a Data Matrix grid to scan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ScanViewModel.self) { viewModel in
                ResultView(viewModel: viewModel)
            }
            .alert(
                "Could not load photo",
                isPresented: Binding(
                    get: { loadError != nil },
                    set: { if !$0 { loadError = nil } }
                ),
                presenting: loadError
            ) { _ in
                Button("OK", role: .cancel) { loadError = nil }
            } message: { error in
                Text(error.message)
            }
            .onChange(of: selectedItem) { _, newValue in
                guard let newValue else { return }
                Task { await handleSelection(newValue) }
            }
            .task {
                // Launch-time photo trim. Failures are logged inside
                // StorageManager, never surfaced — a stale photo cache
                // is not a user-facing error.
                if let storage = storageManager {
                    _ = try? await storage.trim()
                }
            }
        }
    }

    private func handleSelection(_ item: PhotosPickerItem) async {
        defer { selectedItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                loadError = LoadError(message: "The selected item did not contain image data.")
                return
            }
            guard let uiImage = UIImage(data: data) else {
                loadError = LoadError(message: "The selected file is not a recognized image.")
                return
            }
            guard let cgImage = uiImage.cgImage else {
                loadError = LoadError(message: "Could not extract a CGImage from the selected photo.")
                return
            }
            let viewModel = ScanViewModel(storageManager: storageManager)
            viewModel.run(
                cgImage: cgImage,
                layout: settings.defaultLayout,
                validatorPattern: settings.validatorRegex
            )
            path.append(viewModel)
        } catch {
            loadError = LoadError(message: error.localizedDescription)
        }
    }
}

private struct LoadError: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    ScanView()
}
