import XCTest
@testable import DataMatrixScanner

final class AppSettingsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Could not create test UserDefaults suite")
        }
        defaults = suite
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testReaderReturnsCELDefaultsWhenStoreIsEmpty() {
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.validatorRegex, #"^[A-Z]\d{5}$"#)
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))
        XCTAssertTrue(reader.includeProvenanceColumn)
        XCTAssertEqual(reader.retentionDays, 30)
        XCTAssertEqual(reader.maxStorageBytes, 1_073_741_824)
        XCTAssertEqual(reader.gapThresholdMultiplier, 1.5, accuracy: 1e-9)
        XCTAssertEqual(reader.outlierSigmaThreshold, 3.0, accuracy: 1e-9)
    }

    func testSettingsDefaultsConstantsMatchSpec() {
        XCTAssertEqual(SettingsDefaults.validatorRegex, #"^[A-Z]\d{5}$"#)
        XCTAssertEqual(SettingsDefaults.defaultBoxLayoutString, "9x9")
        XCTAssertEqual(SettingsDefaults.defaultBoxLayout, .fixed(rows: 9, cols: 9))
        XCTAssertTrue(SettingsDefaults.includeProvenanceColumn)
        XCTAssertEqual(SettingsDefaults.retentionDays, 30)
        XCTAssertEqual(SettingsDefaults.maxStorageBytes, 1_073_741_824)
        XCTAssertEqual(SettingsDefaults.gapThresholdMultiplier, 1.5, accuracy: 1e-9)
        XCTAssertEqual(SettingsDefaults.outlierSigmaThreshold, 3.0, accuracy: 1e-9)
    }

    // MARK: - defaultLayout decoding

    func testDefaultLayoutDecodesNineByNine() {
        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setDefaultLayoutRaw("9x9")
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))
    }

    func testDefaultLayoutFallsBackForMalformedInputs() {
        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        let reader = UserDefaultsSettingsReader(defaults: defaults)

        writer.setDefaultLayoutRaw("")
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))

        writer.setDefaultLayoutRaw("abc")
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))

        writer.setDefaultLayoutRaw("0x9")
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))

        writer.setDefaultLayoutRaw("9x9x9")
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 9, cols: 9))
    }

    func testDefaultLayoutAutoStorageDecodes() {
        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setDefaultLayoutRaw("auto")
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.defaultLayout, .auto)
    }

    // MARK: - Round-trip

    func testRoundTripFiveBySevenLayout() {
        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setDefaultLayout(.fixed(rows: 5, cols: 7))
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.defaultLayout, .fixed(rows: 5, cols: 7))
    }

    func testWriterPersistsAllScalarKeys() {
        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setValidatorRegex("^X\\d{4}$")
        writer.setIncludeProvenanceColumn(false)
        writer.setRetentionDays(7)
        writer.setMaxStorageBytes(500_000_000)
        writer.setGapThresholdMultiplier(2.0)
        writer.setOutlierSigmaThreshold(4.5)

        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.validatorRegex, "^X\\d{4}$")
        XCTAssertFalse(reader.includeProvenanceColumn)
        XCTAssertEqual(reader.retentionDays, 7)
        XCTAssertEqual(reader.maxStorageBytes, 500_000_000)
        XCTAssertEqual(reader.gapThresholdMultiplier, 2.0, accuracy: 1e-9)
        XCTAssertEqual(reader.outlierSigmaThreshold, 4.5, accuracy: 1e-9)
    }

    // MARK: - Reader sees later writes

    func testReaderReflectsWritesMadeAfterInstantiation() {
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertEqual(reader.retentionDays, 30)

        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setRetentionDays(90)

        XCTAssertEqual(reader.retentionDays, 90,
                       "Reader should pull from UserDefaults at access time")
    }

    // MARK: - Boolean false is preserved (regression: bool(forKey:) returns false for absent keys)

    func testIncludeProvenanceFalseIsDistinctFromAbsent() {
        let reader = UserDefaultsSettingsReader(defaults: defaults)
        XCTAssertTrue(reader.includeProvenanceColumn,
                      "Absent key must yield CEL default (true)")

        let writer = UserDefaultsSettingsWriter(defaults: defaults)
        writer.setIncludeProvenanceColumn(false)
        XCTAssertFalse(reader.includeProvenanceColumn,
                       "Explicit false must be preserved")
    }
}
