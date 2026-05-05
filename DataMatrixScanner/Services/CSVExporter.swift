import Foundation

/// Builds the CSV export string for a scan.
///
/// Two output schemas, gated by `includeProvenance`:
///
/// **Provenance OFF (v1.0 default — used by tests, testbed bundles, public
/// builds)** — `docs/csv-export-spec.md` "Format (default)":
///
/// ```text
/// row,col,code
/// 1,1,A00011
/// 1,2,null
/// ```
///
/// **Provenance ON (v1.1, CEL default)** — adds a `status` column and emits
/// outlier rows for cells with `row == -1, col == -1` plus any
/// `UnplacedDetection` the user has not silently dropped:
///
/// ```text
/// row,col,code,status
/// 1,1,A00011,decoded
/// 1,2,null,empty
/// null,null,Z99999,decoded:outlier
/// ```
///
/// In both schemas the header row is always emitted, line endings are `\n`,
/// and rows are sorted ascending by `(row, col)` with null-row outliers
/// appearing after every regular grid row.
///
/// When `includeProvenance == false`, the new `unplaced:` overload behaves
/// identically to the cells-only one: outlier rows and unplaced detections
/// are NOT added. Outlier rows are a v1.1 provenance feature.
public struct CSVExporter: Sendable {
    /// `true` to emit the v1.1 4-column schema (with `status` and outlier rows).
    public let includeProvenance: Bool

    /// Creates a new exporter. Stateless aside from the schema flag.
    ///
    /// - Parameter includeProvenance: when `true`, emits the v1.1
    ///   provenance schema (`row,col,code,status` header plus outlier rows).
    ///   Defaults to `false` so v1.0 callers retain byte-identical output.
    public init(includeProvenance: Bool = false) {
        self.includeProvenance = includeProvenance
    }

    /// Returns the CSV string for the supplied cells. v1.0-compatible
    /// signature — no unplaced detections.
    ///
    /// - Parameter cells: the grid cells to export. Order is irrelevant —
    ///   the exporter sorts by `(row, col)` internally.
    /// - Returns: the CSV body, including the header.
    public func export(cells: [GridCell]) -> String {
        export(cells: cells, unplaced: [])
    }

    /// Provenance-aware export including outlier rows for unplaced
    /// detections that the user did not discard. v1.1+.
    ///
    /// When `includeProvenance == false`, the `unplaced` parameter is
    /// ignored and output matches the v1.0 schema exactly.
    ///
    /// - Parameters:
    ///   - cells: the grid cells to export.
    ///   - unplaced: detections that did not map to a grid cell.
    /// - Returns: the CSV body, including the header.
    public func export(cells: [GridCell], unplaced: [UnplacedDetection]) -> String {
        if includeProvenance {
            return exportWithProvenance(cells: cells, unplaced: unplaced)
        } else {
            return exportLegacy(cells: cells)
        }
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

    // MARK: - Private — v1.0 schema

    private func exportLegacy(cells: [GridCell]) -> String {
        let rows = cells
            .filter { !$0.isOutlier }
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.col < rhs.col
            }

        var output = "row,col,code\n"
        for cell in rows {
            // TODO(future): if the validator regex is ever relaxed to permit
            // commas, quotes, or newlines, the code column will need RFC 4180
            // quoting. The v1 default `^[A-Z]\d{5}$` is alphanumeric-only.
            output += "\(cell.row),\(cell.col),\(codeValue(for: cell))\n"
        }
        return output
    }

    // MARK: - Private — v1.1 provenance schema

    private func exportWithProvenance(
        cells: [GridCell],
        unplaced: [UnplacedDetection]
    ) -> String {
        let regular = cells
            .filter { !$0.isOutlier }
            .sorted { lhs, rhs in
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                return lhs.col < rhs.col
            }
        let cellOutliers = cells.filter { $0.isOutlier }

        var output = "row,col,code,status\n"
        for cell in regular {
            // TODO(future): RFC 4180 quoting if validator regex permits
            // commas/quotes/newlines.
            output += "\(cell.row),\(cell.col),\(codeValue(for: cell)),\(statusToken(for: cell))\n"
        }
        // Cell-level outliers (decoded codes that didn't map to any (row,col)).
        for cell in cellOutliers {
            output += "null,null,\(codeValue(for: cell)),\(statusToken(for: cell))\n"
        }
        // Unplaced detections — surface every entry, including discarded.
        for detection in unplaced {
            output += unplacedRow(for: detection) + "\n"
        }
        return output
    }

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

    private func statusToken(for cell: GridCell) -> String {
        if cell.isOutlier {
            // Outliers are always decoded codes outside the declared layout.
            return "decoded:outlier"
        }
        switch cell.status {
        case .decoded:
            if cell.userOverride != nil {
                return "edited"
            }
            if cell.userAdded {
                return "manual"
            }
            return "decoded"
        case .empty:
            // A user-populated empty cell is `.decoded` with userAdded; if
            // we still see `.empty` here, no user action was taken.
            return "empty"
        case .unreadable(let reason, _):
            switch reason {
            case .decodeFailed:
                return "unreadable:decode_failed"
            case .validatorRejected(let payload):
                return "unreadable:rejected(\(payload))"
            case .lowConfidence(let payload, _):
                return "unreadable:low_confidence(\(payload))"
            }
        }
    }

    private func unplacedRow(for detection: UnplacedDetection) -> String {
        // Discarded detections are still emitted so the audit trail is intact.
        if case .discarded = detection.action {
            let code = detection.payload ?? "null"
            return "null,null,\(code),discarded"
        }
        switch detection.reason {
        case .spatialOutlier:
            let payload = detection.payload ?? "null"
            return "null,null,\(payload),decoded:outlier"
        case .validatorRejectedOutlier(let decoded):
            return "null,null,null,unreadable:rejected(\(decoded))"
        case .decodeFailed:
            return "null,null,null,unreadable:decode_failed"
        }
    }
}
