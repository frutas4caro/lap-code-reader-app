import os
import SwiftData
import SwiftUI

/// SwiftUI environment key carrying the app-wide `StorageManager`.
///
/// `nil` is the default so previews and unit-tested view hosts that
/// don't construct a `ModelContainer` still build cleanly. Production
/// `App.body` injects a real instance.
private struct StorageManagerKey: EnvironmentKey {
    static let defaultValue: StorageManager? = nil
}

public extension EnvironmentValues {
    /// Shared `StorageManager` for persisting scans + running launch trim.
    /// `nil` when no manager is wired (previews, isolated tests).
    var storageManager: StorageManager? {
        get { self[StorageManagerKey.self] }
        set { self[StorageManagerKey.self] = newValue }
    }
}

@main
struct DataMatrixScannerApp: App {

    private static let logger = Logger(
        subsystem: "com.cel.datamatrixscanner",
        category: "App"
    )

    private let modelContainer: ModelContainer
    private let storageManager: StorageManager

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: StoredScan.self, StoredRawPayload.self, StoredEdit.self
            )
        } catch {
            // SwiftData container construction is critical: a failure
            // here means the device cannot persist. Fall back to an
            // in-memory container so the app still runs (history will
            // be ephemeral) and log so the failure is observable.
            Self.logger.error(
                "ModelContainer construction failed; falling back to in-memory: \(String(describing: error), privacy: .public)"
            )
            do {
                container = try ModelContainer(
                    for: StoredScan.self, StoredRawPayload.self, StoredEdit.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // If even an in-memory container fails to build for our
                // well-known StoredScan models, there is no recovery —
                // SwiftData itself is broken in this process. Surface
                // the underlying error so the failure is diagnosable.
                fatalError("Failed to construct in-memory SwiftData fallback: \(error)")
            }
        }
        self.modelContainer = container
        self.storageManager = StorageManager(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ScanView()
                .environment(\.storageManager, storageManager)
        }
        .modelContainer(modelContainer)
    }
}
