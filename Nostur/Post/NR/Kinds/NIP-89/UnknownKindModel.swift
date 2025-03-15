//
//  UnknownKindModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/01/2024.
//

import Foundation
import NostrEssentials
import CoreData

// UnknownKindModel:
// Fetches all handlers (31990)
// Fetches recommendations (31989) from follows
// Builds a list of suggested apps sorted by recommendations count
class UnknownKindModel: ObservableObject {
    @Published var state: ViewState = .loading
    
    enum ViewState {
        case loading
        case ready(([SuggestedApp],String))
        case timeout
    }
    
    private let backlog = Backlog(timeout: 12.0, auto: true)
    private var didFinishFetchingHandlers = false
    private var didFinishFetchingRecommendations = false
    
    private var appRecommendations: [Event] = [] {
        didSet {
            if didFinishFetchingHandlers {
                if !appHandlers.isEmpty { // appHandlers are required, can be with or without without recommendations
                    self.buildSuggestedApps(unknownKind: self.unknownKind!, pubkey: self.pubkey!, eventId: self.eventId!)
                }
                else {
                    // Could not find any handlers
                    DispatchQueue.main.async { [weak self] in
                        self?.state = .timeout
                    }
                }
            }
        }
    }
    private var appHandlers: [Event] = [] {
        didSet {
            if didFinishFetchingHandlers {
                if !appHandlers.isEmpty { // appHandlers are required, can be with or without without recommendations
                    self.buildSuggestedApps(unknownKind: self.unknownKind!, pubkey: self.pubkey!, eventId: self.eventId!)
                }
                else {
                    // Could not find any handlers
                    DispatchQueue.main.async { [weak self] in
                        self?.state = .timeout
                    }
                }
            }
        }
    }
    
    // STEP 1 (REQ)
    private func fetchAppHandlers(unknownKind: Int64) {
        let reqTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    let filters = [Filters(kinds: [31990], tagFilter: TagFilter(tag: "k", values: ["\(unknownKind)"]), limit: 200)]
                    
                    if let reqJson = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                        req(reqJson)
                    }
                }
            },
            processResponseCommand: { [weak self]  taskId, _, _ in
                bg().perform {
                    guard let self = self else { return }
                    self.didFinishFetchingHandlers = true
                    self.appHandlers = self.fetchApps(kind: unknownKind)
                }
            },
            timeoutCommand: { [weak self] taskId in
                bg().perform {
                    guard let self = self else { return }
                    self.didFinishFetchingHandlers = true
                    self.appHandlers = self.fetchApps(kind: unknownKind)
                }
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2 (REQ)
    private func fetchAppRecommendations(unknownKind: Int64) {
        let reqTask = ReqTask(
            reqCommand: { [weak self] taskId in
                bg().perform {
                    guard let self = self else { return }
                    let filters = [Filters(authors: self.follows!, kinds: [31989], tagFilter: TagFilter(tag: "d", values: ["\(unknownKind)"]), limit: 200)]
                    
                    if let reqJson = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                        req(reqJson)
                    }
                }
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                bg().perform {
                    guard let self = self else { return }
                    self.didFinishFetchingRecommendations = true
                    self.appRecommendations = self.fetchRecommendations(kind: unknownKind)
                }
            },
            timeoutCommand: { [weak self] taskId in
                bg().perform {
                    guard let self = self else { return }
                    self.didFinishFetchingRecommendations = true
                    self.appRecommendations = self.fetchRecommendations(kind: unknownKind)
                }
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 3A (DB)
    private func fetchApps(kind: Int64, context: NSManagedObjectContext = context()) -> [Event] {
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
    
    // STEP 3B (DB)
    private func fetchRecommendations(kind: Int64, context: NSManagedObjectContext = context()) -> [Event] {
        let kindString = "\(kind)"
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == 31989 AND pubkey IN %@ AND mostRecentId == nil", self.follows!)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let apps = (try? context.fetch(request)) ?? []
        
        return apps.filter {
            // Only apps which have tag ["k", "<kind here>"]
            $0.fastTags.first(where: { $0.0 == "d" && $0.1 == kindString }) != nil
        }
    }
    
    // STEP 4
    // Take all handlers and recommendations, sort apps by recommendations (only web-handlers for now)
    private func buildSuggestedApps(unknownKind: Int64, pubkey: String, eventId: String) {
        bg().perform { [weak self] in
            guard let self else { return }
            let decoder = JSONDecoder()
            let suggestedApps = self.appHandlers
                .compactMap({ (handler: Event) -> SuggestedApp? in
                    guard let content = handler.content else { return nil }
                    
                    guard let metaData = try? decoder.decode(NSetMetadata.self, from: content.data(using: .utf8, allowLossyConversion: false)!) else {
                        return nil
                    }
                    
                    let logoUrl: URL? = if let picture = metaData.picture {
                        URL(string: picture)
                    }
                    else {
                        nil
                    }
                    
                    guard let webUrl = self.resolveWebUrl(handler: handler) else { return nil }
                    
                    return SuggestedApp(
                        id: handler.aTag,
                        name: (metaData.name ?? metaData.display_name) ?? "",
                        description: metaData.about,
                        logoUrl: logoUrl,
                        openUrl: webUrl,
                        recommendedBy: self.appRecommendations.reduce([], { (partialResult: [(Pubkey, URL)], recommendation: Event) in
                            if let aRef = recommendation.fastTags.first(where: { $0.0 == "a" })?.1,
                               aRef == handler.aTag,
                               let pfp = NRState.shared.loggedInAccount?.followingCache[recommendation.pubkey]?.pfpURL
                            {
                                return partialResult + [(recommendation.pubkey, pfp)]
                            }
                            return partialResult
                        }))
                })
                .sorted(by: { $0.recommendedBy.count > $1.recommendedBy.count })
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .ready((suggestedApps, self.alt ?? "Unknown post type (kind: \(self.unknownKind!))"))
            }
        }
    }
    
    private var unknownKind: Int64?
    private var eventId: String?
    private var pubkey: String?
    private var dTag: String?
    private var alt: String?
    private var follows: Set<String>?
    
    @MainActor
    public func load(unknownKind: Int64, eventId: String, pubkey: String, dTag: String?, alt: String?) {
        self.unknownKind = unknownKind
        self.eventId = eventId
        self.pubkey = pubkey
        self.dTag = dTag
        self.alt = alt
        self.follows = NRState.shared.loggedInAccount?.followingPublicKeys ?? []
        
        self.fetchAppHandlers(unknownKind: unknownKind)
        self.fetchAppRecommendations(unknownKind: unknownKind)
    }
    
    // Check if the handler handlers web links and return to URL or nil
    private func resolveWebUrl(handler: Event) -> URL? {
        let webHandlers = handler.fastTags.filter { $0.0 == "web" }
        
        if let dTag = self.dTag, let naddrHandler = webHandlers.first(where: { $0.2 == "naddr" }) {
            guard let naddr = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(self.unknownKind!), pubkey: self.pubkey!, dTag: dTag)
            else { return nil }
            guard let webUrl = URL(string: naddrHandler.1.replacingOccurrences(of: "<bech32>", with: naddr.identifier))
            else { return nil }
            return webUrl
        }
        else if let neventHandler = webHandlers.first(where: { $0.2 == "nevent" }) {
            guard let nevent = try? NostrEssentials.ShareableIdentifier("nevent", id: self.eventId!)
            else { return nil }
            guard let webUrl = URL(string: neventHandler.1.replacingOccurrences(of: "<bech32>", with: nevent.identifier))
            else { return nil }
            return webUrl
        }
        else if let noteHandler = webHandlers.first(where: { $0.2 == "note" }) {
            guard let note = try? NostrEssentials.ShareableIdentifier("note", id: self.eventId!)
            else { return nil }
            guard let webUrl = URL(string: noteHandler.1.replacingOccurrences(of: "<bech32>", with: note.identifier))
            else { return nil }
            return webUrl
        }
        else if let noteHandler = webHandlers.first { // if nothing just try as note
            guard let note = try? NostrEssentials.ShareableIdentifier("note", id: self.eventId!)
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
    public var recommendedBy:[(Pubkey, URL)] = []
}
