import Foundation

enum LocationError: LocalizedError {
    case empty
    case unsupportedURL
    case notDirectory
    case unavailable

    var errorDescription: String? {
        switch self {
        case .empty: L10n.text("Enter a folder path.")
        case .unsupportedURL: L10n.text("Only local file paths are supported.")
        case .notDirectory: L10n.text("This path is not a folder.")
        case .unavailable: L10n.text("This folder cannot be opened.")
        }
    }
}

actor LocalPathResolver {
    func resolve(_ input: String, relativeTo currentDirectory: URL) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocationError.empty }

        let candidate: URL
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), url.isFileURL else {
                throw LocationError.unsupportedURL
            }
            candidate = url
        } else {
            let expanded = (trimmed as NSString).expandingTildeInPath
            candidate = expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded, isDirectory: true)
                : currentDirectory.appendingPathComponent(expanded, isDirectory: true)
        }

        let resolved = candidate.standardizedFileURL
        let fileManager = FileManager()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            throw LocationError.unavailable
        }
        guard isDirectory.boolValue else { throw LocationError.notDirectory }
        do {
            _ = try fileManager.contentsOfDirectory(atPath: resolved.path)
        } catch {
            throw LocationError.unavailable
        }
        return resolved
    }
}
