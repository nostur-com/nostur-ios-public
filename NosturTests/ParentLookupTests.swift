import CoreData
import SwiftUI
import Testing
import Vision
@testable import Nostur

@MainActor
@Suite(.serialized)
struct ParentLookupTests {
    private let parentId = "24c54bfe192a2e3af5b96a31ef3e33b788cb26fb904c7f4a79571bc02687b9df"

    @Test func profileParentRequestDoesNotRequireDefinitionTag() throws {
        let pubkey = "b7ed68b062de6b4a12e51fd5285c1e1e0ed0e5128cda93ab11b4150b55ed32fc"
        for kind in [0, 3, 10002, 30023] {
            let request = RequestMessage.getArticle(pubkey: pubkey, kind: kind, definition: "", subscriptionId: "parent")
            let data = try #require(request.data(using: .utf8))
            let message = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
            let filter = try #require(message[2] as? [String: Any])
            #expect(filter["authors"] as? [String] == [pubkey])
            #expect(filter["kinds"] as? [Int] == [kind])
            if kind == 30023 {
                #expect(filter["#d"] as? [String] == [""])
            }
            else {
                #expect(filter["#d"] == nil)
            }
        }
    }

    @available(iOS 16.0, *)
    @Test func profileParentRendersWithoutEmbeddingItself() async throws {
        let context = bg()
        let post = await context.perform {
            let event = Event(context: context)
            event.id = String(repeating: "b", count: 64)
            event.pubkey = "b7ed68b062de6b4a12e51fd5285c1e1e0ed0e5128cda93ab11b4150b55ed32fc"
            event.kind = 0
            event.content = "{\"name\":\"Profile parent\"}"
            event.tagsSerialized = "[]"
            defer { context.delete(event) }
            return NRPost(event: event, withFooter: false, isPreview: true)
        }
        // Verify the actual rendered card contains its description. The old
        // self-embedding path instead renders a spinner and starts another fetch.
        let renderer = ImageRenderer(content: KindResolver(nrPost: post, hideFooter: true)
            .environment(\.nxViewingContext, [.preview, .screenshot])
            .frame(width: 350))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let request = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        #expect(text.contains("Profile update"))
    }

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
