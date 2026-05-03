import Foundation

/// Read-only view of user-configurable settings, free of SwiftUI dependencies.
///
/// Services like `PayloadValidator`, `GridInferencer`, and `StorageManager`
/// depend on this protocol rather than `AppSettings` so they can be exercised
/// from non-SwiftUI contexts (TestBed CLI, unit tests, background tasks).
///
/// Implementations must read from their backing store at call time so that
/// changes made through `AppSettings` (or directly via `UserDefaults`)
/// propagate without requiring service re-instantiation.
public protocol SettingsReader: Sendable {
    /// Current validator regex pattern.
    var validatorRegex: String { get }
    /// Current default `BoxLayout` for new scans.
    var defaultLayout: BoxLayout { get }
    /// Whether the CSV exporter should include the `status` column.
    var includeProvenanceColumn: Bool { get }
    /// Photo retention window in days.
    var retentionDays: Int { get }
    /// Photo storage cap in bytes.
    var maxStorageBytes: Int { get }
    /// Gap threshold multiplier for auto-mode row/column clustering.
    var gapThresholdMultiplier: Double { get }
    /// Outlier sigma threshold for fixed-mode detection-to-position mapping.
    var outlierSigmaThreshold: Double { get }
}

/// `SettingsReader` backed by a `UserDefaults` instance.
///
/// Defaults to `UserDefaults.standard`; tests can inject a private suite.
/// Every property reads from `UserDefaults` at access time, so writes made
/// elsewhere (e.g. via `AppSettings`'s `@AppStorage` properties) are
/// immediately visible.
public struct UserDefaultsSettingsReader: SettingsReader, @unchecked Sendable {
    private let defaults: UserDefaults

    /// Creates a reader bound to the given `UserDefaults` instance.
    /// - Parameter defaults: the backing store (default: `.standard`).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var validatorRegex: String {
        defaults.string(forKey: SettingsKeys.validatorRegex)
            ?? SettingsDefaults.validatorRegex
    }

    public var defaultLayout: BoxLayout {
        let raw = defaults.string(forKey: SettingsKeys.defaultBoxLayout)
            ?? SettingsDefaults.defaultBoxLayoutString
        return BoxLayout.fromStorageString(raw) ?? SettingsDefaults.defaultBoxLayout
    }

    public var includeProvenanceColumn: Bool {
        if defaults.object(forKey: SettingsKeys.includeProvenanceColumn) == nil {
            return SettingsDefaults.includeProvenanceColumn
        }
        return defaults.bool(forKey: SettingsKeys.includeProvenanceColumn)
    }

    public var retentionDays: Int {
        if defaults.object(forKey: SettingsKeys.retentionDays) == nil {
            return SettingsDefaults.retentionDays
        }
        return defaults.integer(forKey: SettingsKeys.retentionDays)
    }

    public var maxStorageBytes: Int {
        if defaults.object(forKey: SettingsKeys.maxStorageBytes) == nil {
            return SettingsDefaults.maxStorageBytes
        }
        return defaults.integer(forKey: SettingsKeys.maxStorageBytes)
    }

    public var gapThresholdMultiplier: Double {
        if defaults.object(forKey: SettingsKeys.gapThresholdMultiplier) == nil {
            return SettingsDefaults.gapThresholdMultiplier
        }
        return defaults.double(forKey: SettingsKeys.gapThresholdMultiplier)
    }

    public var outlierSigmaThreshold: Double {
        if defaults.object(forKey: SettingsKeys.outlierSigmaThreshold) == nil {
            return SettingsDefaults.outlierSigmaThreshold
        }
        return defaults.double(forKey: SettingsKeys.outlierSigmaThreshold)
    }
}

/// Type-erased writer companion to `SettingsReader` for tests and the
/// (rare) non-SwiftUI code paths that need to mutate settings.
///
/// In production, mutation is expected to flow through SwiftUI
/// `@AppStorage` bindings on `AppSettings`. This struct exists so tests
/// can populate a private `UserDefaults` suite without instantiating
/// SwiftUI machinery.
public struct UserDefaultsSettingsWriter {
    private let defaults: UserDefaults

    /// Creates a writer bound to the given `UserDefaults` instance.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Writes the validator regex pattern.
    public func setValidatorRegex(_ value: String) {
        defaults.set(value, forKey: SettingsKeys.validatorRegex)
    }

    /// Writes the default layout using its `storageString` form.
    public func setDefaultLayout(_ value: BoxLayout) {
        defaults.set(value.storageString, forKey: SettingsKeys.defaultBoxLayout)
    }

    /// Writes the raw layout storage string (used by tests for malformed inputs).
    public func setDefaultLayoutRaw(_ raw: String) {
        defaults.set(raw, forKey: SettingsKeys.defaultBoxLayout)
    }

    /// Writes the provenance-column toggle.
    public func setIncludeProvenanceColumn(_ value: Bool) {
        defaults.set(value, forKey: SettingsKeys.includeProvenanceColumn)
    }

    /// Writes the retention-days value.
    public func setRetentionDays(_ value: Int) {
        defaults.set(value, forKey: SettingsKeys.retentionDays)
    }

    /// Writes the storage cap in bytes.
    public func setMaxStorageBytes(_ value: Int) {
        defaults.set(value, forKey: SettingsKeys.maxStorageBytes)
    }

    /// Writes the gap-threshold multiplier.
    public func setGapThresholdMultiplier(_ value: Double) {
        defaults.set(value, forKey: SettingsKeys.gapThresholdMultiplier)
    }

    /// Writes the outlier sigma threshold.
    public func setOutlierSigmaThreshold(_ value: Double) {
        defaults.set(value, forKey: SettingsKeys.outlierSigmaThreshold)
    }
}
