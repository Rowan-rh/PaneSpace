import Foundation

/// Folder-first ordering used by every browser view. Pure and nonisolated so it can run off the
/// main actor for large folders.
enum FileItemSorter {
    static func sorted(_ items: [FileItem], by sort: FileSort, ascending: Bool) -> [FileItem] {
        guard items.count > 1 else { return items }
        // Sorting indices over prepared keys avoids copying large structs and re-bridging strings
        // on every comparison, which made folders with tens of thousands of items slow.
        let isFolder = items.map(\.isFolder)
        let order: [Int]
        switch sort {
        case .name:
            order = sortedIndices(items.map { $0.name as NSString }, isFolder: isFolder, ascending: ascending) {
                $0.localizedStandardCompare($1 as String)
            }
        case .kind:
            order = sortedIndices(items.map { $0.kind as NSString }, isFolder: isFolder, ascending: ascending) {
                $0.localizedStandardCompare($1 as String)
            }
        case .date:
            order = sortedIndices(items.map(\.modificationDate), isFolder: isFolder, ascending: ascending, compare: compareOptional)
        case .size:
            order = sortedIndices(items.map(\.fileSize), isFolder: isFolder, ascending: ascending, compare: compareOptional)
        }
        return order.map { items[$0] }
    }

    private static func sortedIndices<Key>(
        _ keys: [Key],
        isFolder: [Bool],
        ascending: Bool,
        compare: (Key, Key) -> ComparisonResult
    ) -> [Int] {
        let wanted: ComparisonResult = ascending ? .orderedAscending : .orderedDescending
        return keys.indices.sorted { lhs, rhs in
            if isFolder[lhs] != isFolder[rhs] { return isFolder[lhs] }
            return compare(keys[lhs], keys[rhs]) == wanted
        }
    }

    /// Missing values compare as larger than present ones, as the pane always has.
    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }
}
