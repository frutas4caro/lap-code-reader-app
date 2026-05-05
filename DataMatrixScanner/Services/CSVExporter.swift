import Foundation

/// Builds the v1.0 CSV export string for a scan's `[GridCell]`.
///
/// The v1.0 schema is the **provenance-OFF** format documented in
/// `docs/csv-export-spec.md`:
///
/// ```text
/// row,col,code
/// 1,1,A00011
/// 1,2,null
/// ```
///
/// - Header is always emitted.
/// - Cells are sorted ascending by `row`, then `col`.
/// - Decoded payloads (or `userOverride` when present) appear in the
///   `code` column. Unreadable / empty cells render the literal string
///   `null`. Never blank.
/// - Outlier cells (`row == -1, col == -1`) are **omitted** from v1.0
///   output. Provenance status, outlier rows, and edit-tracking land in
///   the v1.1 cut — TODO(dms-jxg).
public struct CSVExporter: Sendable {
    /// Creates a new exporter. `CSVExporter` is stateless.
    public init() {}

    /// Returns the CSV string for the supplied cells. Line endings are
    /// `\n` (Unix); the result is UTF-8 safe.
    ///
    /// - Parameter cells: the grid cells to export. Order is irrelevant —
    ///   the exporter sorts by `(row, col)` internally.
    /// - Returns: the CSV body, including the `row,col,code` header.
    public func export(cells: [GridCell]) -> String {
        let rows = cells
            .filter { !$0.isOutlier }
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.col < rhs.col
            }

        var output = "row,col,code\n"
        for cell in rows {
            output += "\(cell.row),\(cell.col),\(codeValue(for: cell))\n"
        }
        return output
    }

    /// Returns the v1.0 export filename for a given timestamp.
    ///
    /// Format: `DataMatrix_<ISO8601-no-colons>.csv`, e.g.
    /// `DataMatrix_2026-04-26T143022.csv`. Colons are stripped from the
    /// time component because they are illegal on several filesystems.
    ///
    /// - Parameter date: the timestamp to embed. Defaults to `Date()`.
    public static func filename(for date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "Z", with: "")
        return "DataMatrix_\(stamp).csv"
    }

    // MARK: - Private

    private func codeValue(for cell: GridCell) -> String {
        if let override = cell.userOverride {
            return override
        }
        switch cell.status {
        case .decoded(let code):
            return code.payload
        case .unreadable, .empty:
            return "null"
        }
    }
}
