import CoreData
import Testing
@testable import Nostur

@MainActor
@Suite(.serialized)
struct ParentLookupTests {
    private let parentId = "24c54bfe192a2e3af5b96a31ef3e33b788cb26fb904c7f4a79571bc02687b9df"

    @Test func invalidResolvedParentDoesNotReplaceKnownReference() {
        #expect(!NRPost.matchesParentReference(parentId, id: "", aTag: ""))
        #expect(!NRPost.matchesParentReference(parentId, id: String(repeating: "a", count: 64), aTag: ""))
        #expect(NRPost.matchesParentReference(parentId, id: parentId, aTag: ""))
        let aTag = "30023:\(String(repeating: "b", count: 64)):article"
        #expect(NRPost.matchesParentReference(aTag, id: parentId, aTag: aTag))
        #expect(!NRPost.matchesParentReference(aTag, id: "", aTag: aTag))
    }

    @Test func cacheRejectsObjectWhoseIDNoLongerMatchesItsKey() async {
        let context = bg()
        await context.perform {
            let key = String(repeating: "e", count: 64)
            let event = Event(context: context)
            event.id = key
            EventCache.shared.setObject(for: key, value: event)
            defer {
                EventCache.shared.removeValue(forKey: key)
                context.delete(event)
            }
            #expect(EventRelationsQueue.shared.getAwaitingBgEvent(byId: key, context: context) === event)
            // The dictionary key survives even when a managed object's attributes disappear.
            event.id = ""
            #expect(EventRelationsQueue.shared.getAwaitingBgEvent(byId: key, context: context) == nil)
            #expect(EventCache.shared.retrieveObject(at: key) == nil)
        }
    }

    @Test func missingCachedParentCanBeImportedAgain() async {
        let context = bg()
        await context.perform {
            let key = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + String(repeating: "f", count: 32)
            let stale = Event(context: context)
            stale.id = ""
            EventCache.shared.setObject(for: key, value: stale)
            Importer.shared.existingIds[key] = EventState(status: .SAVED)
            defer {
                EventCache.shared.removeValue(forKey: key)
                Importer.shared.existingIds[key] = nil
                context.delete(stale)
            }
            #expect(Event.fetchThreadParent(reference: key, context: context) == nil)
            #expect(Importer.shared.existingIds[key] == nil)
        }
    }
}
