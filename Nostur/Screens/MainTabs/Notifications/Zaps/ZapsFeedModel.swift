//
//  ZapsFeedModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/05/2024.
//

import SwiftUI
import Combine

class ZapsFeedModel: ObservableObject {
    @Published public var postOrProfileZaps: [PostOrProfileZaps] = []
    

    private var pubkey: String?
    public var account: CloudAccount? // Main context

    // bg
    public var mostRecentZapCreatedAt: Int64 {
        allZapEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }
    private var allZapEvents: [Event] = []
    
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.feedUpdates
            .filter { $0.type == .Zaps && $0.accountPubkey == self.pubkey }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation {
                    self.load(limit: 500)
                }
            }
            .store(in: &subscriptions)
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                withAnimation {
                    self.load(limit: 500)
                }
            }
            .store(in: &subscriptions)
    }
    
    public func setup(pubkey: String) {
        self.pubkey = pubkey
        self.account = AccountsState.shared.accounts.first(where: { $0.publicKey == pubkey })
    }
    
    public func load(limit: Int?, includeSpam: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard let pubkey else { return }
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(
                format: "otherPubkey == %@ AND kind == 9735 AND NOT fromPubkey IN %@",
                pubkey,
                AppState.shared.bgAppState.blockedPubkeys
            )
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allZapEvents = ((try? bgContext.fetch(r1)) ?? [])
                .filter { includeSpam || !$0.isSpam }
            
            let eventsZapped: [Event] = allZapEvents
                .compactMap { $0.zappedEventId }
                .uniqued(on: \.self)
                .compactMap { Event.fetchEvent(id: $0, context: bgContext) }
            
            let uniqueEventsZapped: Set<Event> = Set(eventsZapped)
        
            let postZaps: [GroupedPostZaps] = uniqueEventsZapped.map { zappedEvent in
                GroupedPostZaps(
                    zaps: self.allZapEvents
                        .filter { $0.zappedEventId == zappedEvent.id }
                        .reduce(into: [String: (fromPubkey: String, amount: Int64, zap: Event)]()) { (result, zap) in
                            if let fromPubkey = zap.fromPubkey {
                                if let zapInfo = result[fromPubkey] {
                                    result[fromPubkey] = (fromPubkey: fromPubkey, amount: zapInfo.zap.amount + zap.amount, zap: zap) // add
                                }
                                else {
                                    result[fromPubkey] = (fromPubkey: fromPubkey, amount: zap.amount, zap: zap) // create
                                }
                            }
                        }
                        .values
                        .sorted(by: { $0.zap.created_at > $1.zap.created_at })
                        .map { (fromPubkey, amount, zap) in
                            return SingleZap(
                                id: fromPubkey,
                                fromNRContact: NRContact.instance(of: fromPubkey),
                                createdAt: zap.created_at,
                                sats: Double(amount),
                                content: zap.content ?? "")
                        },
                    nrPost: NRPost(event: zappedEvent)
                )
            }
            .sorted(by: { $0.mostRecentCreatedAt > $1.mostRecentCreatedAt })
            
            let profileZaps: [SingleZap] = allZapEvents
                .filter { $0.zappedEventId == nil }
                .compactMap { zapEvent in
                    if let zapFromPubkey = zapEvent.fromPubkey {
                        return (zapFromPubkey, zapEvent)
                    }
                    return nil
                }
                .map { (zapFromPubkey: String, zapEvent: Event) in
                    SingleZap(
                        id: zapEvent.id,
                        fromNRContact: NRContact.instance(of: zapFromPubkey),
                        createdAt: zapEvent.created_at,
                        sats: Double(zapEvent.amount),
                        content: zapEvent.content ?? ""
                    )
                }
            
            let postOrProfileZaps: [PostOrProfileZaps] = (postZaps.map { PostOrProfileZaps(post: $0) } + profileZaps.map { PostOrProfileZaps(profile: $0) }).sorted(by: { $0.mostRecentCreatedAt > $1.mostRecentCreatedAt })
            
            let mostRecentZapCreatedAt = self.mostRecentZapCreatedAt
            
            DispatchQueue.main.async {
                self.postOrProfileZaps = postOrProfileZaps
                if let completion {
                    completion(mostRecentZapCreatedAt)
                }
            }
        }
    }
    
//    public func fetchNewer() {
//        bg().perform { [weak self] in
//            guard let self else { return }
//            let fetchNewerTask = ReqTask(
//                reqCommand: { [weak self] (taskId) in
//                    guard let self, let pubkey = self.pubkey else { return }
//                    req(RM.getMentions(
//                        pubkeys: [pubkey],
//                        kinds: [9735],
//                        limit: 5000,
//                        subscriptionId: taskId,
//                        since: NTimestamp(timestamp: Int(self.allZapEvents.first?.created_at ?? 0))
//                    ))
//                },
//                processResponseCommand: { [weak self] (taskId, _, _) in
//                    guard let self else { return }
//                    L.og.debug("🟠🟠🟠 processResponseCommand \(taskId)")
//                    self.load(limit: 5000)
//                },
//                timeoutCommand: { [weak self] taskId in
//                    guard let self else { return }
//                    self.load(limit: 5000)
//                })
//
//            self.backlog.add(fetchNewerTask)
//            fetchNewerTask.fetch()
//        }
//    }
    
    public func showMore() {
        // TODO: Implement solution for gap reactions 60d ago and 223d ago caused by: We have reactions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let pubkey else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allZapEvents.last?.created_at {
                req(RM.getMentions(
                    pubkeys: [pubkey],
                    kinds: [9735],
                    limit: 500,
                    until: NTimestamp(timestamp: Int(until))
                ))
            }
            else {
                req(RM.getMentions(pubkeys: [pubkey], kinds: [9735], limit: 500))
            }
            
            self.load(limit: 500)
        }
    }
}

struct SingleZap: Identifiable {
    public let id: String
    public let fromNRContact: NRContact
    public let createdAt: Int64
    public let sats: Double
    public let content: String // zap message
}

class GroupedPostZaps: ObservableObject, Identifiable {
    public var id: String { nrPost.id }
    @Published public var zaps: [SingleZap]
    public let nrPost: NRPost
    public var mostRecentCreatedAt: Int64 {
        zaps.sorted(by: { $0.createdAt > $1.createdAt } ).first?.createdAt ?? 0
    }
    
    public init(zaps: [SingleZap], nrPost: NRPost) {
        self.zaps = zaps
        self.nrPost = nrPost
    }
}


struct PostOrProfileZaps: Identifiable {
    public var id: String {
        if type == .Post, let post = post {
            return post.id
        }
        if type == .Profile, let profile = profile {
            return profile.id
        }
        return UUID().uuidString
    }
    public var type: PostOrProfileZap {
        if post != nil { return .Post }
        if profile != nil { return .Profile }
        return .Unknown
    }
    
    public var post: GroupedPostZaps?
    public var profile: SingleZap?
    
    public var mostRecentCreatedAt: Int64 {
        if let post {
            return post.mostRecentCreatedAt
        }
        if let profile {
            return profile.createdAt
        }
        return 0
    }
}

enum PostOrProfileZap {
    case Post
    case Profile
    case Unknown
}
