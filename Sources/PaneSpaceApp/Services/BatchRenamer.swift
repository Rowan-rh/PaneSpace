import Foundation

/// Applies a previewed batch rename through a provider.
///
/// Every item is first moved to a unique temporary name and only then to its final name, so
/// swaps such as "a" ↔ "b" and case-only changes never collide with another item of the batch.
/// If any step fails, completed steps are reversed so the folder returns to its original names.
struct BatchRenamer: Sendable {
    let provider: FileProviding

    struct Failure: LocalizedError {
        let underlying: Error
        /// Items that could not be returned to their original names after the failure.
        let unrecoveredItems: [URL]

        var errorDescription: String? {
            if unrecoveredItems.isEmpty {
                return L10n.format(
                    "The items could not be renamed, and their original names were restored: %@",
                    underlying.localizedDescription
                )
            }
            return L10n.format(
                "The items could not be renamed, and %lld items kept temporary names: %@",
                Int64(unrecoveredItems.count),
                underlying.localizedDescription
            )
        }
    }

    /// Returns the final URL of every renamed item, keyed by its original URL.
    func apply(_ plan: BatchRenamePlan) async throws -> [URL: URL] {
        let entries = plan.changedEntries
        guard !entries.isEmpty else { return [:] }
        guard plan.canApply else { throw FileProviderError.invalidName }

        let token = UUID().uuidString.prefix(8)
        // Each step records where the item is now and how to get it back.
        var staged: [(original: URL, current: URL)] = []
        var finished: [(original: URL, final: URL)] = []
        do {
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                let temporary = try await provider.rename(
                    entry.source,
                    to: ".panespace-rename-\(token)-\(index)"
                )
                staged.append((entry.source, temporary))
            }
            for (index, entry) in entries.enumerated() {
                let final = try await provider.rename(staged[index].current, to: entry.newName)
                staged[index].current = final
                finished.append((entry.source, final))
            }
        } catch {
            let unrecovered = await restore(staged)
            throw Failure(underlying: error, unrecoveredItems: unrecovered)
        }
        return Dictionary(uniqueKeysWithValues: finished.map { ($0.original, $0.final) })
    }

    /// Moves items back in two phases as well, since restored names may be taken by items that
    /// already have their new names.
    private func restore(_ staged: [(original: URL, current: URL)]) async -> [URL] {
        let token = UUID().uuidString.prefix(8)
        var parked: [(original: URL, current: URL)] = []
        var unrecovered: [URL] = []
        for (index, step) in staged.enumerated() {
            do {
                let temporary = try await provider.rename(step.current, to: ".panespace-restore-\(token)-\(index)")
                parked.append((step.original, temporary))
            } catch {
                unrecovered.append(step.current)
            }
        }
        for step in parked {
            do {
                _ = try await provider.rename(step.current, to: step.original.lastPathComponent)
            } catch {
                unrecovered.append(step.current)
            }
        }
        return unrecovered
    }
}
