import Foundation

/// Validates decoded Data Matrix payloads against a user-configurable regex.
///
/// `PayloadValidator` compiles its pattern once at initialization and exposes
/// a fast `matches(_:)` check used by the scan pipeline to partition raw
/// detections into decoded vs. validator-rejected sets. Rejected payloads are
/// never silently dropped — they flow downstream as
/// `CellStatus.unreadable(.validatorRejected(...))`.
///
/// The CEL default pattern is `^[A-Z]\d{5}$`. The pattern is read from
/// `UserDefaults` under the key declared by `SettingsKeys.validatorRegex`,
/// which is also the key used by the Settings store (`@AppStorage`).
///
/// ## Malformed patterns
/// If the supplied pattern fails to compile (for example, `"["`), the
/// initializer does NOT crash. The validator stores a `nil` regex,
/// `isPatternValid` returns `false`, and `matches(_:)` returns `false` for
/// every input. The UI is expected to surface `isPatternValid == false` so
/// the user can correct the pattern.
///
/// `PayloadValidator` is a `final class` conforming to `Sendable`.
/// `NSRegularExpression` is documented as thread-safe by Apple, so the
/// compiled regex can be shared across concurrent decode tasks.
public final class PayloadValidator: @unchecked Sendable {

    /// The pattern this validator was constructed with.
    public let pattern: String

    /// `true` when `pattern` compiled successfully; `false` for malformed
    /// patterns. When `false`, `matches(_:)` returns `false` for all inputs.
    public var isPatternValid: Bool { regex != nil }

    /// The CEL default validator regex. Matches a single uppercase letter
    /// followed by exactly five digits (e.g. `A00011`).
    public static let celDefaultPattern: String = #"^[A-Z]\d{5}$"#

    /// `UserDefaults` key under which the active regex pattern is stored.
    /// Shared with the Settings store `@AppStorage` binding via
    /// `SettingsKeys.validatorRegex` — this constant aliases that key so
    /// callers in the Services layer don't need to import the Settings module.
    public static let userDefaultsKey: String = SettingsKeys.validatorRegex

    private let regex: NSRegularExpression?

    /// Compiles `pattern` as a regular expression. If compilation fails, the
    /// validator is constructed in an "always rejects" state — see the type
    /// doc comment.
    /// - Parameter pattern: a regular expression string. Anchors (`^`, `$`)
    ///   are honored; an unanchored pattern matches anywhere in the input.
    public init(pattern: String) {
        self.pattern = pattern
        self.regex = try? NSRegularExpression(pattern: pattern, options: [])
    }

    /// Reads the active pattern from `userDefaults` (key
    /// `SettingsKeys.validatorRegex`), falling back to ``celDefaultPattern``
    /// when unset.
    /// - Parameter userDefaults: the `UserDefaults` instance to read from.
    ///   Defaults to `.standard`. Tests can pass a suite-name instance for
    ///   isolation.
    public convenience init(userDefaults: UserDefaults = .standard) {
        let stored = userDefaults.string(forKey: PayloadValidator.userDefaultsKey)
        let pattern: String
        if let stored = stored, !stored.isEmpty {
            pattern = stored
        } else {
            pattern = PayloadValidator.celDefaultPattern
        }
        self.init(pattern: pattern)
    }

    /// Returns `true` if `payload` matches the compiled pattern.
    ///
    /// Returns `false` when the pattern is invalid (see `isPatternValid`)
    /// or when no match is found. The pattern's own anchors determine
    /// whether matching is full-string (`^...$`) or substring.
    /// - Parameter payload: a decoded Data Matrix payload.
    public func matches(_ payload: String) -> Bool {
        guard let regex = regex else { return false }
        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        return regex.firstMatch(in: payload, options: [], range: range) != nil
    }
}
