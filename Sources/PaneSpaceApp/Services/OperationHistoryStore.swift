import Foundation

/// Reads and writes operation history as JSON in Application Support, off the main actor.
actor OperationHistoryStore {
    private struct Archive: Codable {
        static let currentVersion = 1
        let version: Int
        let records: [OperationRecord]
    }

    private let fileURL: URL

    init(fileURL: URL = OperationHistoryStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "org.panespace.app"
        return support
            .appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("OperationHistory.json")
    }

    /// Missing, unreadable, or newer-format files start an empty history instead of failing.
    func load() -> [OperationRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == Archive.currentVersion else { return [] }
        return archive.records
    }

    func save(_ records: [OperationRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Archive(version: Archive.currentVersion, records: records))
        try data.write(to: fileURL, options: .atomic)
    }
}
