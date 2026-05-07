import Foundation
import SwiftData
import UIKit
import XCTest
@testable import DataMatrixScanner

/// Shared fixtures for all `StorageManager` test cases. Subclassing
/// keeps each per-area `XCTestCase` under SwiftLint's type-body limit.
@MainActor
class StorageManagerTestCase: XCTestCase {

    // swiftlint:disable implicitly_unwrapped_optional
    var tempRoot: URL!
    var filesystem: DirectoryFilesystem!
    var defaultsSuiteName: String!
    var settings: UserDefaultsSettingsReader!
    var defaults: UserDefaults!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        tempRoot = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appending(
            path: "StorageManagerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        filesystem = DirectoryFilesystem(scansRoot: tempRoot)

        defaultsSuiteName = "StorageManagerTests-\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: defaultsSuiteName) else {
            XCTFail("could not create UserDefaults suite")
            return
        }
        defaults = suite
        settings = UserDefaultsSettingsReader(defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        super.tearDown()
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([StoredScan.self, StoredRawPayload.self, StoredEdit.self])
        let config = ModelConfiguration(
            "StorageManagerTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    func makeManager(
        clock: @escaping () -> Date = { Date() }
    ) throws -> StorageManager {
        let container = try makeContainer()
        return StorageManager(
            container: container,
            filesystem: filesystem,
            settings: settings,
            clock: clock
        )
    }

    func makeImage(
        size: CGSize = CGSize(width: 32, height: 32),
        color: UIColor = .red
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func makeScanResult(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        annotated: Bool = false,
        cells: [GridCell]? = nil,
        layout: BoxLayout = .fixed(rows: 9, cols: 9),
        validatorRegex: String = #"^[A-Z]\d{5}$"#
    ) -> ScanResult {
        let bbox = CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)
        let detected = DetectedCode(payload: "A00011", boundingBox: bbox, confidence: 0.9)
        let defaultCells: [GridCell] = [
            GridCell(row: 1, col: 1, status: .decoded(detected)),
            GridCell(row: 1, col: 2, status: .empty),
            GridCell(
                row: 2,
                col: 1,
                status: .unreadable(
                    reason: .validatorRejected(decodedPayload: "AOO011"),
                    boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.05, height: 0.05)
                )
            ),
            GridCell(
                row: 2,
                col: 2,
                status: .unreadable(
                    reason: .decodeFailed,
                    boundingBox: CGRect(x: 0.3, y: 0.1, width: 0.05, height: 0.05)
                )
            )
        ]
        return ScanResult(
            id: id,
            timestamp: timestamp,
            sourceImage: makeImage(),
            annotatedImage: annotated ? makeImage(color: .green) : nil,
            cells: cells ?? defaultCells,
            unplaced: [],
            csv: "row,col,code\n1,1,A00011\n",
            layoutMode: layout,
            validatorRegex: validatorRegex,
            quality: ScanQualityReport(
                decodedCount: 1,
                rejectedByValidatorCount: 1,
                expectedCount: 81,
                outlierCount: 0,
                principalAxisAngle: 0,
                confidenceFloor: 0.9,
                warnings: []
            )
        )
    }
}

extension StorageManager {
    /// Pins a scan from outside the actor for setup convenience. Lives
    /// in the test target via `@testable` so it doesn't widen the public
    /// API. Persists the change immediately.
    func pinForTesting(id: UUID) async throws -> Bool {
        guard let scan = try await load(id: id) else { return false }
        scan.isPinned = true
        let ctx = scan.modelContext
        try ctx?.save()
        return true
    }
}
