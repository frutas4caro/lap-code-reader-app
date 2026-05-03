import SwiftUI

/// SwiftUI-facing settings facade backed by `@AppStorage`.
///
/// Inject a single instance into views via `@StateObject` (or pass through
/// the environment) and bind individual properties to controls in
/// `SettingsView`. Each property is a thin `@AppStorage` wrapper, so writes
/// are persisted to `UserDefaults.standard` immediately and any
/// `SettingsReader` (e.g. `UserDefaultsSettingsReader`) sees the change on
/// its next read.
///
/// The class is `@MainActor` because `@AppStorage` is `@MainActor`-bound on
/// iOS 17. Background services should depend on `SettingsReader` rather
/// than this type.
@MainActor
public final class AppSettings: ObservableObject {

    /// Validator regex applied to decoded payloads.
    @AppStorage(SettingsKeys.validatorRegex)
    public var validatorRegex: String = SettingsDefaults.validatorRegex

    /// Storage form of the default layout (`"auto"` or `"<rows>x<cols>"`).
    ///
    /// Bind this to a SwiftUI `Picker` and use `defaultLayout` for the
    /// decoded value. Round-trips via `BoxLayout.storageString` /
    /// `BoxLayout.fromStorageString(_:)`.
    @AppStorage(SettingsKeys.defaultBoxLayout)
    public var defaultBoxLayout: String = SettingsDefaults.defaultBoxLayoutString

    /// Whether CSV exports include the `status` provenance column.
    @AppStorage(SettingsKeys.includeProvenanceColumn)
    public var includeProvenanceColumn: Bool = SettingsDefaults.includeProvenanceColumn

    /// Photo-file retention window in days.
    @AppStorage(SettingsKeys.retentionDays)
    public var retentionDays: Int = SettingsDefaults.retentionDays

    /// Photo-file storage cap in bytes.
    @AppStorage(SettingsKeys.maxStorageBytes)
    public var maxStorageBytes: Int = SettingsDefaults.maxStorageBytes

    /// Multiplier applied to median spacing in auto-mode 1D gap clustering.
    @AppStorage(SettingsKeys.gapThresholdMultiplier)
    public var gapThresholdMultiplier: Double = SettingsDefaults.gapThresholdMultiplier

    /// Outlier sigma threshold for fixed-mode position assignment.
    @AppStorage(SettingsKeys.outlierSigmaThreshold)
    public var outlierSigmaThreshold: Double = SettingsDefaults.outlierSigmaThreshold

    /// Creates an `AppSettings` bound to `UserDefaults.standard`.
    public init() {}

    /// Decoded form of `defaultBoxLayout`. Falls back to the CEL default
    /// `(9, 9)` when the stored string is malformed (e.g. user-corrupted
    /// `UserDefaults`).
    public var defaultLayout: BoxLayout {
        BoxLayout.fromStorageString(defaultBoxLayout) ?? SettingsDefaults.defaultBoxLayout
    }
}
