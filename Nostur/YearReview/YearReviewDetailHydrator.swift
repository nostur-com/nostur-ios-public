import Foundation
import CoreData
import NostrEssentials

/// Hydrate a single report highlight, never the entire archive. All managed object
/// access and normal import handlers run inside the supplied context's perform.
enum YearReviewDetailHydrator {
    static func restore(post: YearReviewPost, archive: YearReviewArchive, blocked: Set<String>,
                        context: NSManagedObjectContext) async throws {
        try Task.checkCancellation()
        guard let snapshot = try await archive.event(id: post.id) else { return }
        try await context.perform {
            if Event.fetchEvent(id: post.id, context: context) == nil {
                let original = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(snapshot))
                _ = Event.saveEvent(event: original, context: context)
                try context.save()
            }
        }
        var cursor = ""
        let root = await context.perform {
            Event.fetchEvent(id: post.id, context: context)?.replyToRootId ?? post.id
        }
        while true {
            try Task.checkCancellation()
            let page = try await archive.detailPage(to: post.id, coordinate: post.coordinate, after: cursor)
            guard page.cursor != cursor else { break }
            cursor = page.cursor
            for offset in stride(from: 0, to: page.events.count, by: 25) {
                try Task.checkCancellation()
                let batch = Array(page.events[offset..<min(offset + 25, page.events.count)])
                try await context.perform {
                    for snapshot in batch where !blocked.contains(snapshot.pubkey) {
                        let event: Event
                        if let existing = Event.fetchEvent(id: snapshot.id, context: context) { event = existing }
                        else {
                            let original = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(snapshot))
                            event = Event.saveEvent(event: original, context: context, countReaction: false)
                        }
                        if snapshot.kind == 7, snapshot.tagValues("e").isEmpty,
                           let coordinate = post.coordinate, snapshot.tagValues("a").last == coordinate {
                            event.reactionToId = post.id
                            ViewUpdates.shared.relatedUpdates.send(RelatedUpdate(type: .Reactions, eventId: post.id))
                        }
                        // Legacy replies may name only their immediate parent. We have
                        // verified their ancestor chain in the archive's thread index;
                        // fill the derived cache root so the detail tree can find them.
                        if page.replyIds.contains(snapshot.id), YearReviewKinds.replies.contains(snapshot.kind), snapshot.parentId != nil,
                           event.replyToRootId == nil {
                            event.replyToRootId = root
                        }
                    }
                    if context.hasChanges { try context.save() }
                }
                await Task.yield()
            }
        }
        // Restored reactions may already be represented by the retained footer
        // counter. Reconcile with actual rows instead of incrementing it again.
        try await context.perform {
            let query = Event.fetchRequest()
            query.predicate = NSPredicate(format: "kind == 7 AND reactionToId == %@ AND deletedById == nil AND groupId == nil AND otherId == nil AND content != %@ AND NOT pubkey IN %@ AND NOT kTag IN {4,14,15}", post.id, "-", blocked)
            let available = Set(try context.fetch(query).map(\.id)).count
            if let target = Event.fetchEvent(id: post.id, context: context) {
                let count = max(target.likesCount, Int64(available))
                if count != target.likesCount {
                    target.likesCount = count
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: post.id, likes: count))
                }
            }
            if context.hasChanges { try context.save() }
        }
    }
}
