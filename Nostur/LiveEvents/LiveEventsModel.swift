//
//  LiveEventsModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import Foundation
import SwiftUI
import Combine
import NostrEssentials

// Fetch live events/activities
class LiveEventsModel: ObservableObject {
    
    static public let shared = LiveEventsModel()
    
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let EVENTS_LIMIT = 250
    private var subscriptions = Set<AnyCancellable>()

    @Published var dismissedLiveEvents: Set<String> = [] { // aTags
        didSet {
            self.nrLiveEvents = nrLiveEvents.filter { !self.dismissedLiveEvents.contains($0.id) }
        }
    }
    
    @Published var nrLiveEvents: [NRLiveEvent] = [] {
        didSet {
            if oldValue.count != nrLiveEvents.count {
                updateLiveSubscription()
            }
            livePubkeys = Set(nrLiveEvents
                .filter { $0.status == "live" }
                .flatMap { $0.participantsOrSpeakers }  // Flatten all participants or speakers into a single array
                .map { $0.pubkey })                     // Extract the pubkey from each Contact
        }
    }
    
    // To make PFPs "Live" in other viewsa
    @Published var livePubkeys: Set<String> = []
    
    private init() {
        self.backlog = Backlog(timeout: 5.0, auto: true, backlogDebugName: "LiveEventsModel")
        self.follows = Nostur.follows()
        
        self.listenForReplacableEventUpdates()
        self.listenForBlocklistUpdates()
        
        receiveNotification(.scenePhaseActive)
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .throttle(for: .seconds(15.0), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                self?.updateLiveSubscription()
            }
            .store(in: &subscriptions)
    }
    
    private func fetchFromDB(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = AccountsState.shared.loggedInAccount?.pubkey else { return }
        
        let blockedPubkeys = blocks()
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "(created_at > %i OR pubkey == %@) AND kind == 30311 AND mostRecentId == nil AND NOT pubkey IN %@", agoTimestamp, accountPubkey, blockedPubkeys)
        
        let bgContext = bg()
        bgContext.perform { [weak self]  in
            guard let self else { return }
            
            guard let events = try? bgContext.fetch(fr) else { return }
            
            let nrLiveEvents: [NRLiveEvent] = events
                .filter { !self.dismissedLiveEvents.contains($0.aTag) } // don't show dismissed events
                .filter {
                    if $0.isLive() { return true } // IS LIVE
                    if $0.isPlannedNotInPast() { return true } // OR IS PLANNED BUT NOT TOO FAR IN THE PAST
                    return false
                }
                .filter { hasSpeakerOrHostInFollows($0, follows: self.follows) || (accountPubkey == $0.pubkey) }
                .sorted(by: { $0.created_at > $1.created_at })
                .uniqued(on: { $0.aTag })
                .map { NRLiveEvent(event: $0) }
                .filter { !blockedPubkeys.contains($0.hostPubkey) } // also catch "host" in p-tags blocked
                .filter {
                    // hide if missing title and summary
                    if $0.title == nil && $0.summary == nil { return false }
                    return true
                }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.nrLiveEvents = nrLiveEvents
            }
        }
    }
    
    private var agoTimestamp: Int {
        Int(Date().timeIntervalSince1970 - (14400)) // Only with recent 4 hours
    }
    
    public func fetchFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Live Event created by follows
        let createdByTask = ReqTask(
            debounceTime: 0.5,
            timeout: 3.0,
            subscriptionId: "LIVE-FOLLOWS",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                
                let follows = self.follows.count <= 1950 ? self.follows : Set(self.follows.shuffled().prefix(1950))
                
                nxReq(Filters(
                    authors: follows,
                    kinds: Set([30311]),
                    since: agoTimestamp
                ), subscriptionId: taskId, isActiveSubscription: true)
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.fetchFromDB(onComplete)
#if DEBUG
                L.og.debug("LIVE feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                self?.fetchFromDB(onComplete)
#if DEBUG
                L.og.debug("LIVE feed: timeout")
#endif
            })
        
        // Live Event invited or participated by follows (TODO: should check proof)
        let participatingTask = ReqTask(
            debounceTime: 0.5,
            timeout: 3.0,
            subscriptionId: "LIVE-PARTICIPATING",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                
                let follows = self.follows.count <= 1950 ? self.follows : Set(self.follows.shuffled().prefix(1950))
                
                nxReq(Filters(
                    kinds: Set([30311]),
                    tagFilter: TagFilter(tag: "p", values: follows),
                    since: agoTimestamp
                ), subscriptionId: taskId, isActiveSubscription: true)
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.fetchFromDB(onComplete)
#if DEBUG
                L.og.debug("LIVE feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                self?.fetchFromDB(onComplete)
#if DEBUG
                L.og.debug("LIVE feed: timeout")
#endif
            })
        
        backlog.add(createdByTask)
        backlog.add(participatingTask)
        createdByTask.fetch()
        participatingTask.fetch()
    }
    
    @MainActor
    public func load() {
#if DEBUG
        L.og.debug("LIVE feed: load()")
#endif
        self.follows = Nostur.follows()
        self.nrLiveEvents = []
        self.fetchFromRelays()
    }
    
    // for after account change // TODO: Handle account change
    @MainActor
    public func reload() {
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.nrLiveEvents = []
        self.fetchFromRelays()
    }
    
    private func updateLiveSubscription() {
        guard SettingsStore.shared.enableLiveEvents else { return }
        guard !nrLiveEvents.isEmpty else {
            req(NostrEssentials.ClientMessage(type: .CLOSE, subscriptionId: "LIVEEVENTS").json()!)
            return
        }
        if let cm = NostrEssentials
            .ClientMessage(type: .REQ,
                           subscriptionId: "LIVEEVENTS",
                           filters: nrLiveEvents.map { Filters(
                            authors: [$0.pubkey],
                            kinds: [30311],
                            tagFilter: TagFilter(tag: "d", values: [$0.dTag])
                           )
            }).json() {
            req(cm, activeSubscriptionId: "LIVEEVENTS")
        }
    }
        
    private func listenForReplacableEventUpdates() {
        ViewUpdates.shared.replacableEventUpdate
            .sink { [weak self] event in
                guard SettingsStore.shared.enableLiveEvents else { return }
                guard let self else { return }
                
                // We should be in bg() already, here (?)
                let nEvent = event.toNEvent() // TODO: This is NEvent (MessageParser) to Event (Importer) to NEvent (here), need to fix better
                let aTag = event.aTag
                
                if Set(self.nrLiveEvents.map { $0.id }).contains(aTag) { // update existing event
                    
                    
                    // Only continue if we have aTag, and it is older
                    guard (self.nrLiveEvents.first(where: { $0.id == aTag && $0.nEvent.createdAt.timestamp < nEvent.createdAt.timestamp })) != nil else { return }
                    
                    if (event.isLive() || event.isPlanned()) { // update if still live or planned
                        
                        let pubkeysOnStage = event.pubkeysOnStage()
                        let participantsOrSpeakers = event.participantsOrSpeakers()
                        let fastPs = event.fastPs
                        let totalParticipants = if let currentParticipantsTag = event.fastTags.first(where: { $0.0 == "current_participants" }) {
                            Int(currentParticipantsTag.1) ?? 0
                        }
                        else {
                            event.fastPs.count
                        }
                        let title = !(event.eventTitle ?? "").isEmpty ? event.eventTitle : nil // title or nil, treat "" also as nil
                        let summary = !(event.eventSummary ?? "").isEmpty ? event.eventSummary : nil // summary or nil, treat "" also as nil
                        let url: URL? = if let urlTag = event.fastTags.first(where: { $0.0 == "streaming" }), let url = URL(string: urlTag.1) {
                            url
                        }
                        else {
                            nil
                        }
                        let eventJson = event.toNEvent().eventJson()
                        let liveKitBaseUrl = event.liveKitBaseUrl()
                        let liveKitJoinUrl = event.liveKitJoinUrl()
                        let streamingUrl = event.streamingUrl()
                        let webUrl = event.webUrl()
                        let thumbUrl = event.eventImage
                        let streamStatus = event.streamStatus()
                        let recordingUrl = event.recordingUrl()
                        let liveKitConnectUrl = event.liveKitConnectUrl()
                        let scheduledAt: Date? = if event.isPlanned(),
                                                        let startsTag = event.fastTags.first(where: { $0.0 == "starts" }),
                                                        let starts = Double(startsTag.1) {
                            Date(timeIntervalSince1970: starts)
                        }
                        else {
                            nil
                        }
                        
                        // if planned but in the past, remove
                        if let scheduledAt, event.isPlanned() && scheduledAt > Date().addingTimeInterval(-10800) { // 3 hours ago
                            self.nrLiveEvents.removeAll(where: { $0.id == aTag && $0.nEvent.createdAt.timestamp < nEvent.createdAt.timestamp }) // Only remove older
                        }
                        else if let nrLiveEvent = self.nrLiveEvents.first(where: { $0.id == aTag && $0.nEvent.createdAt.timestamp < nEvent.createdAt.timestamp }) { // update event (only if existing is older)
                            DispatchQueue.main.async {
                                nrLiveEvent.objectWillChange.send()
                                nrLiveEvent.loadReplacableData((nEvent: nEvent,
                                                              pubkeysOnStage: pubkeysOnStage,
                                                              participantsOrSpeakers: participantsOrSpeakers,
                                                              title: title,
                                                              summary: summary,
                                                              fastPs: fastPs,
                                                              totalParticipants: totalParticipants,
                                                              url: url,
                                                              eventJson: eventJson,
                                                              liveKitJoinUrl: liveKitJoinUrl,
                                                              streamingUrl: streamingUrl,
                                                              webUrl: webUrl,
                                                              thumbUrl: thumbUrl,
                                                              streamStatus: streamStatus,
                                                              recordingUrl: recordingUrl,
                                                              liveKitBaseUrl: liveKitBaseUrl,
                                                              liveKitConnectUrl: liveKitConnectUrl,
                                                              scheduledAt: scheduledAt
                                                             ))
                            }
                        }
                    }
                    else { // else remove
                        DispatchQueue.main.async {
                            self.nrLiveEvents.removeAll(where: { $0.id == aTag && $0.nEvent.createdAt.timestamp < nEvent.createdAt.timestamp })
                        }
                    }
                }
                else if !self.dismissedLiveEvents.contains(aTag) && (event.isLive() || event.isPlannedNotInPast()) && !blocks().contains(event.hostPubkey()) { // insert new live or planned event
                    let nrLiveEvent = NRLiveEvent(event: event)
                    
                    DispatchQueue.main.async {
                        self.nrLiveEvents.insert(nrLiveEvent, at: 0)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func listenForBlocklistUpdates() {
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.nrLiveEvents = self.nrLiveEvents
                    .filter { !blockedPubkeys.contains($0.pubkey) && !blockedPubkeys.contains($0.hostPubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
        
}


func hasSpeakerOrHostInFollows(_ event: Event, follows: Set<String>) -> Bool {
    if (follows.contains(event.pubkey)) { return true }
    
    // event.pubkey can be ANY since REQ was on p-tags not .pubkey, so need to apply WoT filter
    if event.inWoT == false { return false }

    let speakerOrHostPubkeys: Set<String> = Set(event.fastPs
        // Check for "speaker" or "host" on p-tags
        .filter { fastP in
            if !isValidPubkey(fastP.1) {
                return false
            }
            return (fastP.3?.lowercased() == "speaker" || fastP.3?.lowercased() == "host")
        }
        .map { $0.1 })
    
    
    return follows.intersection(speakerOrHostPubkeys).count > 0
}
