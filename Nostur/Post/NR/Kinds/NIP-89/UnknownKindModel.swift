//
//  UnknownKindModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/01/2024.
//

import Foundation
import NostrEssentials
import CoreData

// Discovers web apps that advertise support for a post kind.
class UnknownKindModel: ObservableObject {
    @Published var state: ViewState = .loading
    
    enum ViewState {
        case loading
        case ready(([SuggestedApp],String))
        case timeout
    }
    
    private let backlog = Backlog(timeout: 8.0, auto: true, backlogDebugName: "UnknownKindModel")
    @MainActor
    func load(unknownKind: Int64, eventId: String, pubkey: String, dTag: String?, alt: String?) {
        let context = bg()
        let updateApps: () -> Void = { [weak self] in
            context.perform { [weak self] in
                guard let self else { return }
                let apps = self.fetchApps(kind: unknownKind, context: context)
                let suggestedApps = self.buildSuggestedApps(apps, kind: unknownKind, eventId: eventId, pubkey: pubkey, dTag: dTag)
                let title = alt ?? String(localized: "Unknown post type (kind: \(unknownKind))")
                let state: ViewState = apps.isEmpty ? .timeout : .ready((suggestedApps, title))
                DispatchQueue.main.async { [weak self] in
                    self?.state = state
                }
            }
        }
        let reqTask = ReqTask(
            reqCommand: { taskId in
                context.perform {
                    let filters = [Filters(kinds: [31990], tagFilter: TagFilter(tag: "k", values: ["\(unknownKind)"]), limit: 200)]
                    
                    if let reqJson = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                        req(reqJson)
                    }
                }
            },
            processResponseCommand: { _, _, _ in updateApps() },
            timeoutCommand: { _ in updateApps() })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    private func fetchApps(kind: Int64, context: NSManagedObjectContext) -> [Event] {
        let kindString = "\(kind)"
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == 31990 AND mostRecentId == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let apps = (try? context.fetch(request)) ?? []
        
        return apps.filter {
            // Only apps which have tag ["k", "<kind here>"]
            $0.fastTags.first(where: { $0.0 == "k" && $0.1 == kindString }) != nil
        }
    }
    
    private func buildSuggestedApps(_ handlers: [Event], kind: Int64, eventId: String, pubkey: String, dTag: String?) -> [SuggestedApp] {
        let decoder = JSONDecoder()
        return handlers.compactMap { handler in
            guard let content = handler.content,
                  let metadata = try? decoder.decode(NSetMetadata.self, from: Data(content.utf8)),
                  let webURL = resolveWebUrl(handler: handler, kind: kind, eventId: eventId, pubkey: pubkey, dTag: dTag),
                  BrowserSigningPolicy.origin(webURL) != nil else { return nil }

            return SuggestedApp(
                id: handler.aTag,
                name: (metadata.name ?? metadata.display_name) ?? "",
                description: metadata.about,
                logoUrl: metadata.picture.flatMap { URL(string: $0) },
                openUrl: webURL,
                publisher: handler.pubkey
            )
        }
    }

    private func resolveWebUrl(handler: Event, kind: Int64, eventId: String, pubkey: String, dTag: String?) -> URL? {
        let webHandlers = handler.fastTags.filter { $0.0 == "web" }
        
        if let dTag, let naddrHandler = webHandlers.first(where: { $0.2 == "naddr" }) {
            guard let naddr = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(kind), pubkey: pubkey, dTag: dTag)
            else { return nil }
            guard let webUrl = URL(string: naddrHandler.1.replacingOccurrences(of: "<bech32>", with: naddr.identifier))
            else { return nil }
            return webUrl
        }
        else if let neventHandler = webHandlers.first(where: { $0.2 == "nevent" }) {
            guard let nevent = try? NostrEssentials.ShareableIdentifier("nevent", id: eventId)
            else { return nil }
            guard let webUrl = URL(string: neventHandler.1.replacingOccurrences(of: "<bech32>", with: nevent.identifier))
            else { return nil }
            return webUrl
        }
        else if let noteHandler = webHandlers.first(where: { $0.2 == "note" }) {
            guard let note = try? NostrEssentials.ShareableIdentifier("note", id: eventId)
            else { return nil }
            guard let webUrl = URL(string: noteHandler.1.replacingOccurrences(of: "<bech32>", with: note.identifier))
            else { return nil }
            return webUrl
        }
        else if let noteHandler = webHandlers.first { // if nothing just try as note
            guard let note = try? NostrEssentials.ShareableIdentifier("note", id: eventId)
            else { return nil }
            guard let webUrl = URL(string: noteHandler.1.replacingOccurrences(of: "<bech32>", with: note.identifier))
            else { return nil }
            return webUrl
        }
        return nil
    }
}

struct SuggestedApp: Identifiable {
    public let id: String
    public let name: String
    public var description: String?
    public var logoUrl: URL?
    public let openUrl: URL
    public var publisher: Pubkey? = nil
}
