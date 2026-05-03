import Foundation

/// Centralised `UserDefaults` keys for v1 user-configurable settings.
///
/// Both the SwiftUI-facing `AppSettings` (via `@AppStorage`) and the
/// non-SwiftUI `SettingsReader` reference these keys so they stay in sync.
public enum SettingsKeys {
    /// Regex used by `PayloadValidator` to accept/reject decoded payloads.
    public static let validatorRegex = "settings.validatorRegex"
    /// Stable string form of the default `BoxLayout` (e.g. `"9x9"` or `"auto"`).
    public static let defaultBoxLayout = "settings.defaultBoxLayout"
    /// Whether CSV exports include the `status` provenance column.
    public static let includeProvenanceColumn = "settings.includeProvenanceColumn"
    /// Photo-file retention window in days; SwiftData records are kept regardless.
    public static let retentionDays = "settings.retentionDays"
    /// Photo-file storage cap in bytes.
    public static let maxStorageBytes = "settings.maxStorageBytes"
    /// Multiplier applied to median inter-code spacing when auto-clustering rows/cols.
    public static let gapThresholdMultiplier = "settings.gapThresholdMultiplier"
    /// Number of standard deviations beyond which a detection is treated as an outlier.
    public static let outlierSigmaThreshold = "settings.outlierSigmaThreshold"
}

/// CEL-flavoured default values for every key in `SettingsKeys`.
///
/// These values are the source of truth for "fresh install" behaviour and
/// are used by both `AppSettings` (`@AppStorage` defaults) and
/// `SettingsReader` (fallback when a key is absent from `UserDefaults`).
public enum SettingsDefaults {
    /// CEL pattern: one uppercase letter followed by five digits.
    public static let validatorRegex: String = #"^[A-Z]\d{5}$"#
    /// CEL boxes are 9×9.
    public static let defaultBoxLayoutString: String = "9x9"
    /// Decoded form of `defaultBoxLayoutString`.
    public static let defaultBoxLayout: BoxLayout = .fixed(rows: 9, cols: 9)
    /// Provenance column on by default in CEL builds.
    public static let includeProvenanceColumn: Bool = true
    /// 30-day photo retention window.
    public static let retentionDays: Int = 30
    /// 1 GiB storage cap for photo files.
    public static let maxStorageBytes: Int = 1_073_741_824
    /// 1.5× median spacing — see `docs/grid-inference.md`.
    public static let gapThresholdMultiplier: Double = 1.5
    /// 3σ outlier threshold — see `docs/grid-inference.md`.
    public static let outlierSigmaThreshold: Double = 3.0
}
