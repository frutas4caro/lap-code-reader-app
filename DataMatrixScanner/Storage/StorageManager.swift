import Foundation
import SwiftData
import UIKit

// MARK: - Filesystem abstraction

/// Filesystem location strategy for scan photo files.
///
/// Defaults to `Application Support/Scans/` on device; tests inject a
/// temporary directory via `InMemoryFilesystem` (or a custom adapter)
/// so the app's real Application Support tree is never touched.
public protocol StorageFilesystem: Sendable {
    /// Root directory under which `<uuid>/input.jpg` etc. are written.
    /// Implementations SHALL ensure the directory exists when accessed.
    var scansRoot: URL { get }
}

/// Production filesystem rooted at `Application Support/Scans/`.
///
/// The directory is created lazily on first access. The path resolves
/// to `URL.applicationSupportDirectory.appending(path: "Scans")` on
/// iOS 17+.
public struct ApplicationSupportFilesystem: StorageFilesystem {
    public init() {}

    public var scansRoot: URL {
        let base: URL
        if #available(iOS 16.0, *) {
            base = URL.applicationSupportDirectory
        } else {
            // Fallback path; iOS 17+ deployment target makes this branch dead.
            base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let root = base.appending(path: "Scans", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }
}

public extension StorageFilesystem where Self == ApplicationSupportFilesystem {
    /// Sugar for `StorageManager(filesystem: .applicationSupport)`.
    static var applicationSupport: ApplicationSupportFilesystem { .init() }
}

/// `StorageFilesystem` rooted at an explicit URL — used by tests and the
/// TestBed CLI to redirect scan photos away from Application Support.
public struct DirectoryFilesystem: StorageFilesystem {
    public let scansRoot: URL
    public init(scansRoot: URL) {
        self.scansRoot = scansRoot
        try? FileManager.default.createDirectory(
            at: scansRoot,
            withIntermediateDirectories: true
        )
    }
}

// MARK: - Trim reporting

/// Reason a particular scan's photo files were removed during trim.
public enum TrimReason: Sendable, Equatable {
    /// The scan's age (in whole days) exceeded the configured retention window.
    case ageExceeded(scanID: UUID, ageDays: Int)
    /// Total scan storage exceeded `maxStorageBytes`; oldest scans removed first.
    case storageCapExceeded(scanID: UUID)
}

/// Summary of a single trim pass.
public struct TrimReport: Sendable, Equatable {
    /// Number of scans whose photo files were removed.
    public let scansTrimmed: Int
    /// Total bytes reclaimed by the trim pass.
    public let bytesReclaimed: Int64
    /// Per-scan reasons, in the order they were trimmed.
    public let reasons: [TrimReason]

    public init(scansTrimmed: Int, bytesReclaimed: Int64, reasons: [TrimReason]) {
        self.scansTrimmed = scansTrimmed
        self.bytesReclaimed = bytesReclaimed
        self.reasons = reasons
    }

    /// Empty report — no scans were touched.
    public static let empty = TrimReport(scansTrimmed: 0, bytesReclaimed: 0, reasons: [])
}

// MARK: - Errors

/// Errors raised by `StorageManager`.
public enum StorageError: Error, Sendable, Equatable {
    /// `UIImage.jpegData(compressionQuality:)` returned `nil` for the source image.
    case imageEncodingFailed
    /// SwiftData lookup for the supplied id returned no record.
    case recordNotFound(UUID)
}

// MARK: - StorageManager

/// Persists `ScanResult`s to SwiftData and manages their on-disk photo files.
///
/// All work is serialised through the actor: callers may hold a single
/// shared instance across the app. Tests inject an in-memory
/// `ModelContainer` and a temp-directory `StorageFilesystem`; production
/// code uses the shared SwiftData container and `Application Support`.
public actor StorageManager {

    // MARK: Dependencies

    private let container: ModelContainer
    private let filesystem: StorageFilesystem
    private let settings: SettingsReader
    private let clock: () -> Date
    private let fileManager: FileManager
    private let jpegQuality: CGFloat

    // MARK: Init

    /// Creates a storage manager.
    ///
    /// - Parameters:
    ///   - container: SwiftData container backing `StoredScan` persistence.
    ///   - filesystem: where scan photo directories live (default: Application Support).
    ///   - settings: source of `retentionDays` and `maxStorageBytes`.
    ///   - clock: injectable "now" closure so age-based tests don't depend on system time.
    ///   - fileManager: file manager used for I/O (default: `.default`).
    ///   - jpegQuality: JPEG compression quality applied to written images.
    public init(
        container: ModelContainer,
        filesystem: StorageFilesystem = .applicationSupport,
        settings: SettingsReader = UserDefaultsSettingsReader(),
        clock: @escaping () -> Date = { Date() },
        fileManager: FileManager = .default,
        jpegQuality: CGFloat = 0.9
    ) {
        self.container = container
        self.filesystem = filesystem
        self.settings = settings
        self.clock = clock
        self.fileManager = fileManager
        self.jpegQuality = jpegQuality
    }

    // MARK: Public API

    /// Persists a `ScanResult`: writes JPEGs under `<scansRoot>/<uuid>/`
    /// and inserts a `StoredScan` record. Returns the saved record.
    @discardableResult
    public func save(_ result: ScanResult) async throws -> StoredScan {
        let context = ModelContext(container)
        let dir = directory(for: result.id)
        try ensureDirectory(dir)

        // Write source image. JPEG encode failure is fatal — without an
        // image there is no useful record to persist.
        guard let sourceData = result.sourceImage.jpegData(compressionQuality: jpegQuality) else {
            throw StorageError.imageEncodingFailed
        }
        let sourceURL = dir.appending(path: "input.jpg", directoryHint: .notDirectory)
        try sourceData.write(to: sourceURL, options: .atomic)

        // Annotated image is best-effort: if encoding fails we save the
        // record without it rather than aborting the whole save.
        var annotatedRelative: String?
        if let annotated = result.annotatedImage,
           let annotatedData = annotated.jpegData(compressionQuality: jpegQuality) {
            let annotatedURL = dir.appending(path: "annotated.jpg", directoryHint: .notDirectory)
            try annotatedData.write(to: annotatedURL, options: .atomic)
            annotatedRelative = relativePath(for: annotatedURL)
        }

        let stored = StoredScan(
            id: result.id,
            timestamp: result.timestamp,
            sourceImagePath: relativePath(for: sourceURL),
            annotatedImagePath: annotatedRelative,
            rawPayloads: rawPayloads(from: result),
            edits: edits(from: result),
            layoutMode: result.layoutMode.storageString,
            validatorRegexAtCapture: result.validatorRegex,
            isPinned: false
        )
        context.insert(stored)
        try context.save()
        return stored
    }

    /// Loads a single record by id, or `nil` if no such record exists.
    public func load(id: UUID) async throws -> StoredScan? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<StoredScan>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Returns every stored scan ordered newest-first by `timestamp`.
    public func listAll() async throws -> [StoredScan] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<StoredScan>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Deletes the record AND its on-disk photo directory.
    public func delete(id: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<StoredScan>(
            predicate: #Predicate { $0.id == id }
        )
        guard let scan = try context.fetch(descriptor).first else {
            throw StorageError.recordNotFound(id)
        }
        let dir = directory(for: scan.id)
        try? fileManager.removeItem(at: dir)
        context.delete(scan)
        try context.save()
    }

    /// Runs the trim pass.
    ///
    /// Photos for non-pinned scans are removed when:
    /// 1. The scan's age (in whole days, computed against `clock()`) exceeds
    ///    `settings.retentionDays`, OR
    /// 2. After applying (1), total scan-tree size still exceeds
    ///    `settings.maxStorageBytes`; oldest non-pinned scans are removed
    ///    until total bytes are at or under the cap.
    ///
    /// SwiftData records are preserved with `sourceImagePath` and
    /// `annotatedImagePath` set to `nil`. Pinned scans are exempt from
    /// both gates.
    @discardableResult
    public func trim() async throws -> TrimReport {
        let context = ModelContext(container)
        let now = clock()
        let retentionDays = settings.retentionDays
        let maxBytes = Int64(settings.maxStorageBytes)

        let scans = try context.fetch(
            FetchDescriptor<StoredScan>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        )

        var reasons: [TrimReason] = []
        var bytesReclaimed: Int64 = 0

        // Pass 1: age-based trim.
        for scan in scans where !scan.isPinned && scan.sourceImagePath != nil {
            let ageDays = wholeDays(from: scan.timestamp, to: now)
            if ageDays > retentionDays {
                let dir = directory(for: scan.id)
                bytesReclaimed += removeDirectory(dir)
                scan.sourceImagePath = nil
                scan.annotatedImagePath = nil
                reasons.append(.ageExceeded(scanID: scan.id, ageDays: ageDays))
            }
        }

        // Pass 2: storage-cap trim. Re-measure tree from disk so it
        // reflects pass-1 deletions plus any orphaned files. Re-fetch
        // explicitly oldest-first rather than reversing the prior fetch
        // (SwiftData's array views aren't guaranteed to round-trip
        // through `.reversed()` cleanly).
        var totalBytes = directorySize(filesystem.scansRoot)
        if totalBytes > maxBytes {
            let oldestFirst = try context.fetch(
                FetchDescriptor<StoredScan>(
                    sortBy: [SortDescriptor(\.timestamp, order: .forward)]
                )
            )
            for scan in oldestFirst {
                if totalBytes <= maxBytes { break }
                guard !scan.isPinned, scan.sourceImagePath != nil else { continue }
                let dir = directory(for: scan.id)
                let removed = removeDirectory(dir)
                bytesReclaimed += removed
                totalBytes -= removed
                scan.sourceImagePath = nil
                scan.annotatedImagePath = nil
                reasons.append(.storageCapExceeded(scanID: scan.id))
            }
        }

        if !reasons.isEmpty {
            try context.save()
        }
        return TrimReport(
            scansTrimmed: reasons.count,
            bytesReclaimed: bytesReclaimed,
            reasons: reasons
        )
    }

    // MARK: - Path helpers

    /// Absolute on-disk directory for a scan's photo files.
    public nonisolated func directory(for scanID: UUID) -> URL {
        filesystem.scansRoot.appending(
            path: scanID.uuidString,
            directoryHint: .isDirectory
        )
    }

    // MARK: - Private helpers

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Path stored in `StoredScan.sourceImagePath` — relative to scansRoot
    /// so absolute paths don't break across iOS sandbox container churn.
    private func relativePath(for url: URL) -> String {
        let rootPath = filesystem.scansRoot.path(percentEncoded: false)
        let urlPath = url.path(percentEncoded: false)
        if urlPath.hasPrefix(rootPath) {
            let suffix = urlPath.dropFirst(rootPath.count)
            return suffix.hasPrefix("/") ? String(suffix.dropFirst()) : String(suffix)
        }
        return urlPath
    }

    private func wholeDays(from start: Date, to end: Date) -> Int {
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return 0 }
        return Int(interval / 86_400)
    }

    /// Recursively totals file sizes under `url`. Returns 0 if absent.
    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Removes a directory and returns the number of bytes freed.
    @discardableResult
    private func removeDirectory(_ url: URL) -> Int64 {
        let bytes = directorySize(url)
        try? fileManager.removeItem(at: url)
        return bytes
    }

}
