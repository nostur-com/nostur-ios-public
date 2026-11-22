import Foundation

/// Stores stable feed identities independently of names, visibility, and Core Data ordering.
struct FeedMenuOrder {
    private(set) var ids: [String]

    init(rawValue: String) {
        let decoded = (try? JSONDecoder().decode([String].self, from: Data(rawValue.utf8))) ?? []
        var seen = Set<String>()
        ids = decoded.filter { seen.insert($0).inserted }
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    func ordered(_ available: [FeedSwipeSelection]) -> [FeedSwipeSelection] {
        let saved = Set(ids)
        return ids.compactMap { id in available.first { $0.id == id } }
            + available.filter { !saved.contains($0.id) }
    }

    func reordering(_ visible: [FeedSwipeSelection]) -> Self {
        let visibleIds = visible.map(\.id)
        let visibleSet = Set(visibleIds)
        let savedSet = Set(ids)
        let allIds = ids + visibleIds.filter { !savedSet.contains($0) }
        var reordered = visibleIds.makeIterator()
        var result = self
        // Retain hidden feeds in their slots so temporarily disabling a feed or
        // switching accounts does not erase its position.
        result.ids = allIds.map { visibleSet.contains($0) ? reordered.next() ?? $0 : $0 }
        return result
    }
}
