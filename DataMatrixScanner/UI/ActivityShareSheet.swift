import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around `UIActivityViewController` for sharing
/// scan exports (CSV file, etc.) via the system share sheet.
///
/// Used by `ResultView` to surface AirDrop / Mail / Files / Slack
/// destinations for the v1.0 CSV export.
public struct ActivityShareSheet: UIViewControllerRepresentable {
    /// Items to share. Typically a single file `URL`.
    public let activityItems: [Any]

    /// Creates a share sheet for the supplied items.
    ///
    /// - Parameter activityItems: Items handed to `UIActivityViewController`.
    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
