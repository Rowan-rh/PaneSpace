import Foundation

/// How a batch rename derives new names. Extensions are kept unless the rule targets them.
enum BatchRenameRule: Equatable, Sendable {
    case replace(find: String, replacement: String, ignoresCase: Bool, includesExtension: Bool)
    case add(prefix: String, suffix: String)
    /// `base` followed by a counter, for example "Photo 001".
    case format(base: String, separator: String, start: Int, digits: Int)

    func newName(for originalName: String, at index: Int) -> String {
        let (stem, fileExtension) = Self.split(originalName)
        switch self {
        case let .replace(find, replacement, ignoresCase, includesExtension):
            guard !find.isEmpty else { return originalName }
            let options: String.CompareOptions = ignoresCase ? [.caseInsensitive] : []
            if includesExtension {
                return originalName.replacingOccurrences(of: find, with: replacement, options: options)
            }
            return Self.join(
                stem.replacingOccurrences(of: find, with: replacement, options: options),
                fileExtension
            )
        case let .add(prefix, suffix):
            return Self.join(prefix + stem + suffix, fileExtension)
        case let .format(base, separator, start, digits):
            let number = String(start + index)
            let padded = String(repeating: "0", count: max(0, digits - number.count)) + number
            return Self.join(base + separator + padded, fileExtension)
        }
    }

    /// Splits "archive.tar.gz" as Finder does: only the last extension is kept apart, and names
    /// that start with a dot such as ".gitignore" have no extension.
    static func split(_ name: String) -> (stem: String, fileExtension: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let fileExtension = String(name[name.index(after: dot)...])
        guard !fileExtension.isEmpty, !fileExtension.contains(" ") else { return (name, "") }
        return (String(name[..<dot]), fileExtension)
    }

    private static func join(_ stem: String, _ fileExtension: String) -> String {
        fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }
}

enum BatchRenameIssue: Equatable, Sendable {
    case invalidName
    /// Another item in this batch would get the same name.
    case duplicateInBatch
    /// An item outside the batch already uses the name.
    case existingItem

    var message: String {
        switch self {
        case .invalidName: L10n.text("The name is not valid.")
        case .duplicateInBatch: L10n.text("Another renamed item would get this name.")
        case .existingItem: L10n.text("An item with that name already exists.")
        }
    }
}

struct BatchRenameEntry: Identifiable, Equatable, Sendable {
    let source: URL
    let newName: String
    let issue: BatchRenameIssue?

    var id: URL { source }
    var originalName: String { source.lastPathComponent }
    var isChanged: Bool { newName != originalName }
}

/// A previewed batch rename. It never touches the file system; execution uses its entries.
struct BatchRenamePlan: Equatable, Sendable {
    let entries: [BatchRenameEntry]

    /// - Parameters:
    ///   - sources: the items to rename, in the order counters are assigned.
    ///   - existingNames: every name currently in the folder, including the sources.
    init(sources: [URL], rule: BatchRenameRule, existingNames: [String]) {
        let proposed = sources.enumerated().map { index, source in
            (source, rule.newName(for: source.lastPathComponent, at: index)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let sourceKeys = Set(sources.map { Self.comparisonKey($0.lastPathComponent) })
        let occupiedKeys = Set(existingNames.map(Self.comparisonKey)).subtracting(sourceKeys)
        var proposedCounts: [String: Int] = [:]
        for (_, name) in proposed {
            proposedCounts[Self.comparisonKey(name), default: 0] += 1
        }

        entries = proposed.map { source, name in
            let key = Self.comparisonKey(name)
            let issue: BatchRenameIssue?
            if !Self.isValidName(name) {
                issue = .invalidName
            } else if proposedCounts[key, default: 0] > 1 {
                issue = .duplicateInBatch
            } else if occupiedKeys.contains(key) {
                issue = .existingItem
            } else {
                issue = nil
            }
            return BatchRenameEntry(source: source, newName: name, issue: issue)
        }
    }

    /// Wraps entries whose names were already validated.
    init(entries: [BatchRenameEntry]) {
        self.entries = entries
    }

    var hasIssues: Bool { entries.contains { $0.issue != nil } }
    var changedEntries: [BatchRenameEntry] { entries.filter(\.isChanged) }
    var canApply: Bool { !hasIssues && !changedEntries.isEmpty }

    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty &&
            name != "." &&
            name != ".." &&
            !name.contains("/") &&
            !name.contains(":") &&
            !name.contains("\0") &&
            name.utf8.count <= 255
    }

    /// APFS and HFS+ volumes are case-insensitive and normalization-insensitive by default, so
    /// conflicts are detected the same way to avoid a rename failing halfway through.
    static func comparisonKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }
}

struct BatchRenameRequest: Identifiable {
    let id = UUID()
    let targets: [FileItem]
}
