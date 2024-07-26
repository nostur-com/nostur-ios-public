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
    
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let EVENTS_LIMIT = 250
    private var subscriptions = Set<AnyCancellable>()
    private var agoTimestamp: Int?
    private var dismissedLiveEvents: Set<String> = [] // aTags
    
    @Published var nrLiveEvents: [NRLiveEvent] = [] {
        didSet {
            if oldValue.count != nrLiveEvents.count {
                updateLiveSubscription()
            }
        }
    }
    
    public init() {
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = Nostur.follows()
        
        self.listenForReplacableEventUpdates()
        self.listenForBlocklistUpdates()
    }
    
    private func fetchFromDB(_ onComplete: (() -> ())? = nil) {
        guard let agoTimestamp = self.agoTimestamp else { return }
        
        let blockedPubkeys = blocks()
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 30311 AND mostRecentId == nil AND NOT pubkey IN %@", agoTimestamp, blockedPubkeys)
        
        let bgContext = bg()
        bgContext.perform { [weak self]  in
            guard let self else { return }
            
            guard let events = try? bgContext.fetch(fr) else { return }
            
            let nrLiveEvents: [NRLiveEvent] = events
                .filter { !self.dismissedLiveEvents.contains($0.aTag) } // don't show dismissed events
                .filter { $0.fastTags.contains(where: { $0.0 == "status" && $0.1 == "live" })} // only LIVE
                .filter { self.hasSpeakerOrHostInFollows($0) }
                .map { NRLiveEvent(event: $0) }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.nrLiveEvents = nrLiveEvents
            }
        }
    }
    
    private func hasSpeakerOrHostInFollows(_ event: Event) -> Bool {
        if (self.follows.contains(event.pubkey)) { return true }
        
        let speakerOrHostPubkeys: Set<String> = Set(event.fastPs
            .filter { fastP in
                if !isValidPubkey(fastP.1) {
                    return false
                }
                return (fastP.3?.lowercased() == "speaker" || fastP.3?.lowercased() == "host")
            }
            .map { $0.1 })
        
        
        return self.follows.intersection(speakerOrHostPubkeys).count > 0
    }
    
    private func fetchFromRelays(_ onComplete: (() -> ())? = nil) {
        
        self.agoTimestamp = Int(Date().timeIntervalSince1970 - (60 * 60 * 4)) // Only with recent 4 hours
        guard let agoTimestamp = self.agoTimestamp else { return }
        
        let reqTask = ReqTask(
            debounceTime: 0.5,
            timeout: 3.0,
            subscriptionId: "LIVE",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [
                                    Filters(
                                        authors: self.follows, // Live Event created by follows
                                        kinds: Set([30311]),
                                        since: agoTimestamp,
                                        limit: 200
                                    ),
                                    Filters(
                                        kinds: Set([30311]),
                                        tagFilter: TagFilter(tag: "p", values: self.follows), // Live Event invited or participated by follows (TODO: should check proof)
                                        since: agoTimestamp,
                                        limit: 200
                                    ),
                                   ]
                    ).json() {
                    req(cm)
                }
                else {
                    L.og.error("LIVE feed: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.fetchFromDB(onComplete)
                self.backlog.clear()
                L.og.info("LIVE feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.fetchFromDB(onComplete)
                self.backlog.clear()
                L.og.info("LIVE feed: timeout")
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func load() {
        L.og.info("LIVE feed: load()")
        self.follows = Nostur.follows()
        self.nrLiveEvents = []
        self.fetchFromRelays()
    }
    
    // for after account change
    public func reload() {
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.nrLiveEvents = []
        self.fetchFromRelays()
    }
    
    private func updateLiveSubscription() {
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
            req(cm)
        }
    }
        
    private func listenForReplacableEventUpdates() {
        ViewUpdates.shared.replacableEventUpdate
            .sink { [weak self] event in
                guard let self else { return }
                // We should be in bg() already, here (?)
                let aTag = event.aTag
                
                if Set(self.nrLiveEvents.map { $0.id }).contains(aTag) { // update existing event
                    
                    
                    guard (self.nrLiveEvents.first(where: { $0.id == aTag })) != nil else { return }
                    
                    if (event.isLive()) { // update if still live
                        
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
                        let liveKitJoinUrl = event.liveKitJoinUrl()
                        let streamingUrl = event.streamingUrl()
                        let webUrl = event.webUrl()
                        let thumbUrl = event.eventImage
                        let streamStatus = event.streamStatus()
                        let recordingUrl = event.recordingUrl()
                        let liveKitConnectUrl = event.liveKitConnectUrl()
                        
                        if let nrLiveEvent = self.nrLiveEvents.first(where: { $0.id == aTag }) {
                            DispatchQueue.main.async {
                                nrLiveEvent.objectWillChange.send()
                                nrLiveEvent.loadReplacableData((participantsOrSpeakers: participantsOrSpeakers,
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
                                                              liveKitConnectUrl: liveKitConnectUrl
                                                             ))
                            }
                        }
                    }
                    else { // else remove
                        DispatchQueue.main.async {
                            self.nrLiveEvents.removeAll(where: { $0.id == aTag })
                        }
                    }
                }
                else { // insert new live event
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
                self.nrLiveEvents = self.nrLiveEvents.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
        
}
