import XCTest
@testable import DataMatrixScanner

final class PayloadValidatorTests: XCTestCase {

    // MARK: - CEL default pattern

    func test_celDefault_acceptsCanonicalCodes() {
        let validator = PayloadValidator(pattern: PayloadValidator.celDefaultPattern)
        XCTAssertTrue(validator.isPatternValid)
        XCTAssertTrue(validator.matches("A00011"))
        XCTAssertTrue(validator.matches("Z99999"))
        XCTAssertTrue(validator.matches("M12345"))
    }

    func test_celDefault_rejectsLowercase() {
        let validator = PayloadValidator(pattern: PayloadValidator.celDefaultPattern)
        XCTAssertFalse(validator.matches("a00011"))
    }

    func test_celDefault_rejectsLetterOMisread() {
        // Common misread: capital letter O instead of zero.
        let validator = PayloadValidator(pattern: PayloadValidator.celDefaultPattern)
        XCTAssertFalse(validator.matches("AOO011"))
    }

    func test_celDefault_rejectsWrongLength() {
        let validator = PayloadValidator(pattern: PayloadValidator.celDefaultPattern)
        XCTAssertFalse(validator.matches("A0001"))
        XCTAssertFalse(validator.matches("A000111"))
        XCTAssertFalse(validator.matches(""))
    }

    // MARK: - Custom patterns

    func test_customPattern_fourDigits() {
        let validator = PayloadValidator(pattern: #"^\d{4}$"#)
        XCTAssertTrue(validator.isPatternValid)
        XCTAssertTrue(validator.matches("0000"))
        XCTAssertTrue(validator.matches("9912"))
        XCTAssertFalse(validator.matches("123"))
        XCTAssertFalse(validator.matches("12345"))
        XCTAssertFalse(validator.matches("A1234"))
    }

    func test_customPattern_twoLettersFourDigits() {
        let validator = PayloadValidator(pattern: #"^[A-Z]{2}\d{4}$"#)
        XCTAssertTrue(validator.matches("AB1234"))
        XCTAssertFalse(validator.matches("A00011"))
    }

    // MARK: - Malformed patterns

    func test_malformedPattern_doesNotCrash_andRejectsAll() {
        let validator = PayloadValidator(pattern: "[")
        XCTAssertFalse(validator.isPatternValid)
        XCTAssertFalse(validator.matches("A00011"))
        XCTAssertFalse(validator.matches(""))
        XCTAssertFalse(validator.matches("anything"))
    }

    func test_malformedPattern_unmatchedParen() {
        let validator = PayloadValidator(pattern: "(unclosed")
        XCTAssertFalse(validator.isPatternValid)
        XCTAssertFalse(validator.matches("unclosed"))
    }

    // MARK: - UserDefaults round-trip

    private func makeIsolatedDefaults(
        function: String = #function
    ) -> UserDefaults {
        let suiteName = "PayloadValidatorTests.\(function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to allocate UserDefaults suite for tests")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func test_userDefaultsInit_unsetUsesCelDefault() {
        let defaults = makeIsolatedDefaults()
        let validator = PayloadValidator(userDefaults: defaults)
        XCTAssertEqual(validator.pattern, PayloadValidator.celDefaultPattern)
        XCTAssertTrue(validator.matches("A00011"))
        XCTAssertFalse(validator.matches("AOO011"))
    }

    func test_userDefaultsInit_readsStoredPattern() {
        let defaults = makeIsolatedDefaults()
        defaults.set(#"^\d{4}$"#, forKey: PayloadValidator.userDefaultsKey)
        let validator = PayloadValidator(userDefaults: defaults)
        XCTAssertEqual(validator.pattern, #"^\d{4}$"#)
        XCTAssertTrue(validator.matches("1234"))
        XCTAssertFalse(validator.matches("A00011"))
    }

    func test_userDefaultsInit_emptyStringFallsBackToDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set("", forKey: PayloadValidator.userDefaultsKey)
        let validator = PayloadValidator(userDefaults: defaults)
        XCTAssertEqual(validator.pattern, PayloadValidator.celDefaultPattern)
    }
}
