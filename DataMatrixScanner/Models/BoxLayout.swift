import Foundation

/// Per-scan grid layout selection.
///
/// `.auto` lets `GridInferencer` derive both row and column counts
/// from the centroid distribution. `.fixed` forces a declared shape;
/// PCA is then used only to recover orientation.
public enum BoxLayout: Hashable, Codable, Sendable {
    /// Infer row and column counts from the centroid distribution.
    case auto
    /// Declare the grid dimensions; the inferred grid will always
    /// contain exactly `rows × cols` cells.
    case fixed(rows: Int, cols: Int)

    /// Stable string form used in `StoredScan.layoutMode`
    /// (e.g. `"auto"` or `"9x9"`).
    public var storageString: String {
        switch self {
        case .auto:
            return "auto"
        case let .fixed(rows, cols):
            return "\(rows)x\(cols)"
        }
    }

    /// Parses the storage form produced by `storageString`. Returns
    /// `nil` when the string is malformed.
    public static func fromStorageString(_ raw: String) -> BoxLayout? {
        if raw == "auto" {
            return .auto
        }
        let parts = raw.split(separator: "x")
        guard parts.count == 2,
              let rows = Int(parts[0]),
              let cols = Int(parts[1]),
              rows > 0,
              cols > 0
        else {
            return nil
        }
        return .fixed(rows: rows, cols: cols)
    }
}
