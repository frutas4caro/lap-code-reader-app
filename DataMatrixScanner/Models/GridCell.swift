import Foundation

/// A single position in the inferred or declared grid.
///
/// Outlier cells (detections that do not map to any declared
/// `(row, col)` in `.fixed` layout mode) carry `row = -1, col = -1`
/// and `status = .decoded(...)`. They are never silently dropped.
public struct GridCell: Hashable, Codable, Sendable {
    /// 1-based row index. `-1` for outliers.
    public var row: Int
    /// 1-based column index. `-1` for outliers.
    public var col: Int
    /// Current display state of the cell.
    public var status: CellStatus
    /// User-edited payload that takes precedence over `status`.
    public var userOverride: String?
    /// `true` when the user manually populated an originally-empty cell.
    public var userAdded: Bool

    /// Creates a grid cell.
    public init(
        row: Int,
        col: Int,
        status: CellStatus,
        userOverride: String? = nil,
        userAdded: Bool = false
    ) {
        self.row = row
        self.col = col
        self.status = status
        self.userOverride = userOverride
        self.userAdded = userAdded
    }

    /// `true` when this cell represents a spatial outlier in `.fixed`
    /// layout mode (row and column both `-1`).
    public var isOutlier: Bool {
        row == -1 && col == -1
    }
}
