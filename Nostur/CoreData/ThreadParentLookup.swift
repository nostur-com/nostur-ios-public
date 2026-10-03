import CoreData

extension Event {
    /// Call inside the shared background context's perform block. Thread lookup
    /// must use the stored reference even when a cached object or SAVED marker is stale.
    static func fetchThreadParent(reference: String, context: NSManagedObjectContext) -> Event? {
        guard context === bg(), !reference.isEmpty else { return nil }
        if reference.contains(":") {
            return Event.fetchReplacableEvent(aTag: reference, context: context)
        }
        guard reference.count == 64 else { return nil }
        if let cached = EventRelationsQueue.shared.getAwaitingBgEvent(byId: reference, context: context) {
            return cached
        }

        let request = Event.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", reference)
        request.fetchLimit = 1
        do {
            if let event = try context.fetch(request).first {
                EventCache.shared.setObject(for: reference, value: event)
                return event
            }
            // A confirmed database miss must allow a relay response to be
            // imported again rather than discarded as an already-saved duplicate.
            if Importer.shared.existingIds[reference]?.status == .SAVED {
                Importer.shared.existingIds[reference] = nil
            }
        }
        catch {
            // A failed fetch does not prove the event is absent.
        }
        return nil
    }
}
