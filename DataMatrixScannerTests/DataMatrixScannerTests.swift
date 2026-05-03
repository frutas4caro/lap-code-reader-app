import XCTest
@testable import DataMatrixScanner

final class BootstrapTests: XCTestCase {
    func test_appBundleLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
