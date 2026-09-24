import Foundation

/// Finder-style selection over an ordered list of item identifiers.
///
/// The anchor is where a Shift range starts; the cursor is the item keyboard movement continues
/// from. Both are inferred again whenever the selection was changed elsewhere, for example by
/// the system table handling a mouse click, so keyboard extension always starts from what the
/// user sees.
struct ItemSelection<ID: Hashable>: Equatable {
    private(set) var selected: Set<ID>
    private(set) var anchor: ID?
    private(set) var cursor: ID?

    init(selected: Set<ID> = [], anchor: ID? = nil, cursor: ID? = nil) {
        self.selected = selected
        self.anchor = anchor
        self.cursor = cursor
    }

    enum Direction {
        case previous
        case next
    }

    /// Replaces the selection with a single item.
    mutating func select(_ id: ID) {
        selected = [id]
        anchor = id
        cursor = id
    }

    /// Command-click: adds the item, or removes it if it was already selected.
    mutating func toggle(_ id: ID, in order: [ID]) {
        reconcile(with: order)
        if selected.contains(id) {
            selected.remove(id)
            if anchor == id || cursor == id {
                let remaining = order.first { selected.contains($0) }
                anchor = remaining
                cursor = remaining
            }
        } else {
            selected.insert(id)
            anchor = id
            cursor = id
        }
    }

    /// Shift-click: selects the contiguous range from the anchor to the item.
    mutating func extend(to id: ID, in order: [ID]) {
        reconcile(with: order)
        guard let anchor, let anchorIndex = order.firstIndex(of: anchor),
              let targetIndex = order.firstIndex(of: id) else {
            select(id)
            return
        }
        selected = Set(order[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
        cursor = id
    }

    /// Arrow keys. Without `extending` the selection collapses to the neighbouring item; with it
    /// the range between the anchor and the new cursor is selected.
    /// Returns the item that should be scrolled into view, or nil when nothing changed.
    @discardableResult
    mutating func move(_ direction: Direction, extending: Bool, in order: [ID]) -> ID? {
        guard !order.isEmpty else { return nil }
        reconcile(with: order, preferring: direction)
        guard let cursor, let cursorIndex = order.firstIndex(of: cursor) else {
            let first = direction == .next ? order[0] : order[order.count - 1]
            select(first)
            return first
        }

        let nextIndex = direction == .next
            ? min(cursorIndex + 1, order.count - 1)
            : max(cursorIndex - 1, 0)
        let target = order[nextIndex]
        if extending {
            extend(to: target, in: order)
        } else if nextIndex == cursorIndex, selected == [target] {
            return nil
        } else {
            select(target)
        }
        return target
    }

    mutating func selectAll(in order: [ID]) {
        guard !order.isEmpty else { return }
        selected = Set(order)
        if anchor.map({ !selected.contains($0) }) ?? true { anchor = order.first }
        if cursor.map({ !selected.contains($0) }) ?? true { cursor = order.last }
    }

    /// Adopts a selection made outside this type while keeping the anchor and cursor when they
    /// are still part of it.
    mutating func adopt(_ newSelection: Set<ID>) {
        guard newSelection != selected else { return }
        selected = newSelection
        if let anchor, !newSelection.contains(anchor) { self.anchor = nil }
        if let cursor, !newSelection.contains(cursor) { self.cursor = nil }
    }

    private mutating func reconcile(with order: [ID], preferring direction: Direction = .next) {
        let visibleSelection = order.filter { selected.contains($0) }
        guard let first = visibleSelection.first, let last = visibleSelection.last else {
            anchor = nil
            cursor = nil
            return
        }
        let anchorIsValid = anchor.map { selected.contains($0) && order.contains($0) } ?? false
        let cursorIsValid = cursor.map { selected.contains($0) && order.contains($0) } ?? false
        if !anchorIsValid {
            anchor = direction == .next ? first : last
        }
        if !cursorIsValid {
            cursor = direction == .next ? last : first
        }
    }
}
