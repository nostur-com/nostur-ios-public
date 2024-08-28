//
//  NRLiveEvent.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import Foundation
import SwiftUI
import Combine
import NostrEssentials

class NRLiveEvent: ObservableObject, Identifiable, Hashable, Equatable, IdentifiableDestination {
    
    static func == (lhs: NRLiveEvent, rhs: NRLiveEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public var id: String // aTag
    public let pubkey: String
    public let dTag: String
    
    @Published public var participantsOrSpeakers: [NRContact]
    @Published public var totalParticipants: Int
    @Published public var title: String?
    @Published public var summary: String?
    @Published public var fastPs: [FastTag]
    @Published public var url: URL?
    @Published public var thumbUrl: URL?
    
    public var eventJson: String
    public var liveKitJoinUrl: String?
    public var streamingUrl: String?
    public var webUrl: String?
    @Published public var status: String?
    @Published public var scheduledAt: Date?
    
    public var recordingUrl: String?
    public var liveKitConnectUrl: String?
    
    // LiveKit auth token
    @Published public var authToken: String?
    
    private let backlog = Backlog(auto: true)
    private var listenForPresenceSub: AnyCancellable?
    
    init(event: Event) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        self.id = event.aTag
        self.pubkey = event.pubkey
        self.dTag = event.dTag

        self.participantsOrSpeakers = event.participantsOrSpeakers().reversed()
        self.fastPs = event.fastPs
        self.totalParticipants = if let currentParticipantsTag = event.fastTags.first(where: { $0.0 == "current_participants" }) {
            Int(currentParticipantsTag.1) ?? 0
        }
        else {
            event.fastPs.count
        }
        self.title = !(event.eventTitle ?? "").isEmpty ? event.eventTitle : nil // title or nil, treat "" also as nil
        self.summary = !(event.eventSummary ?? "").isEmpty ? event.eventSummary : nil // summary or nil, treat "" also as nil
        self.url = if let urlTag = event.fastTags.first(where: { $0.0 == "streaming" }), let url = URL(string: urlTag.1) {
            url
        }
        else {
            nil
        }
        self.thumbUrl = if let eventImage = event.eventImage {
            URL(string: eventImage)
        }
        else {
            nil
        }
        self.eventJson = event.toNEvent().eventJson()
        self.liveKitJoinUrl = event.liveKitJoinUrl()
        self.streamingUrl = event.streamingUrl()
        self.webUrl = event.webUrl()
        self.status = event.streamStatus()
        self.recordingUrl = event.recordingUrl()
        self.liveKitConnectUrl = event.liveKitConnectUrl()
        
        self.pubkeysOnStage.insert(event.pubkey)
        
        self.scheduledAt = if event.isPlanned(),
                                        let startsTag = event.fastTags.first(where: { $0.0 == "starts" }),
                                        let starts = Double(startsTag.1) {
            Date(timeIntervalSince1970: starts)
        }
        else {
            nil
        }
    }
    
    public func loadReplacableData(_ params: (participantsOrSpeakers: [NRContact],
                                              title: String?,
                                              summary: String?,
                                              fastPs: [(String, String, String?, String?, String?)],
                                              totalParticipants: Int,
                                              url: URL?,
                                              eventJson: String,
                                              liveKitJoinUrl: String?,
                                              streamingUrl: String?,
                                              webUrl: String?,
                                              thumbUrl: String?,
                                              streamStatus: String?,
                                              recordingUrl: String?,
                                              liveKitConnectUrl: String?,
                                              scheduledAt: Date?
                                             )) {
        
        self.objectWillChange.send()
        self.participantsOrSpeakers = params.participantsOrSpeakers
        self.fastPs = params.fastPs
        self.totalParticipants = params.totalParticipants
        self.title = params.title
        self.summary = params.summary
        self.url = params.url
        self.eventJson = params.eventJson
        self.liveKitJoinUrl = params.liveKitJoinUrl
        self.streamingUrl = params.streamingUrl
        self.webUrl = params.webUrl
        self.thumbUrl = if let thumbUrl = params.thumbUrl {
            URL(string: thumbUrl)
        }
        else {
            nil
        }
        self.status = params.streamStatus
        self.recordingUrl = params.recordingUrl
        self.liveKitConnectUrl = params.liveKitConnectUrl
        self.scheduledAt = params.scheduledAt
    }
    
    func role(forPubkey pubkey: String) -> String? {
        return fastPs.first(where: { $0.1 == pubkey })?.3?.capitalized
    }
    
    @MainActor
    public func joinRoom(account: CloudAccount, completion: ((String) -> Void)? = nil) {
        guard let liveKitJoinUrl = self.liveKitJoinUrl else { return }
        
        var nEvent = NEvent(content: "")
        nEvent.publicKey = account.publicKey
        nEvent.kind = .custom(27235)
        nEvent.tags.append(NostrTag(["u", liveKitJoinUrl]))
        nEvent.tags.append(NostrTag(["method", "GET"]))
        
        guard let signedNip98Event = try? account.signEvent(nEvent) else { return }
        
        let jsonString = signedNip98Event.eventJson()
        guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else { return }
        let base64 = jsonData.base64EncodedString()
        let authorizationHeader = "Nostr \(base64)"
        
        Task {
            do {
                let jsonResponse = try await fetchData(from: liveKitJoinUrl, authHeader: authorizationHeader)
                Task { @MainActor in
                    if let authToken = jsonResponse["token"] as? String {
                        self.authToken = authToken
                        completion?(authToken)
                    }
                }
                print("JSON Response: \(jsonResponse)")
            } catch {
                print("Failed to fetch data: \(error.localizedDescription)")
            }
        }

    }
    
    @MainActor
    public func joinRoomAnonymously(keys: NKeys, completion: ((String) -> Void)? = nil) {
        guard let liveKitJoinUrl = self.liveKitJoinUrl else { return }
        
        var nEvent = NEvent(content: "")
        nEvent.publicKey = keys.publicKeyHex()
        nEvent.kind = .custom(27235)
        nEvent.tags.append(NostrTag(["u", liveKitJoinUrl]))
        nEvent.tags.append(NostrTag(["method", "GET"]))
        
        guard let signedNip98Event = try? nEvent.sign(keys) else { return }
        
        let jsonString = signedNip98Event.eventJson()
        guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else { return }
        let base64 = jsonData.base64EncodedString()
        let authorizationHeader = "Nostr \(base64)"
        
        Task {
            do {
                let jsonResponse = try await fetchData(from: liveKitJoinUrl, authHeader: authorizationHeader)
                Task { @MainActor in
                    if let authToken = jsonResponse["token"] as? String {
                        self.authToken = authToken
                        completion?(authToken)
                    }
                }
                print("JSON Response: \(jsonResponse)")
            } catch {
                print("Failed to fetch data: \(error.localizedDescription)")
            }
        }

    }
    
    // Function to fetch data from a given URL
    func fetchData(from urlString: String, authHeader: String) async throws -> [String: Any] {
        // Ensure the URL is valid
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        print(urlString)
        print(authHeader)
        
        // Perform the data task using async/await
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check if a valid response was received
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Ensure data is not nil
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        // Parse the data as JSON
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return json
        } else {
            throw URLError(.cannotParseResponse)
        }
    }
    
    @MainActor
    public func fetchPresenceFromRelays() {
        self.listenForPresence()
        let ago = Int(Date().timeIntervalSince1970 - (60 * 2)) // 2 min ago?
        
        if let cm = NostrEssentials
            .ClientMessage(type: .REQ,
                           subscriptionId: "-DB-ROOMPRESENCE",
                           filters: [
                            Filters(
                                kinds: Set([10312]),
                                tagFilter: TagFilter(tag: "a", values: [self.id]),
                                since: ago,
                                limit: 500
                            )
                           ]
            ).json() {
            req(cm, activeSubscriptionId: "-DB-ROOMPRESENCE")
        }
        else {
            L.og.error("fetchPresentInRoom feed: Problem generating request")
        }
    }
    
    
    
    @Published public var raisedHands: Set<String> = [] // Not used in views? can be private and not @Published?
    @Published public var pubkeysOnStage: Set<String> = []
    @Published public var mutedPubkeys: Set<String> = []
    @Published public var othersPresent: Set<String> = []
    
    var onStage: [NRContact] {
        participantsOrSpeakers.filter { nrContact in
            pubkeysOnStage.contains(nrContact.pubkey)
        }
    }
    
    var listeners: [NRContact] {
        participantsOrSpeakers.filter { nrContact in
            othersPresent.contains(nrContact.pubkey)
        }
    }
    
    @MainActor
    public func listenForPresence() {
        guard listenForPresenceSub == nil else { return }
        listenForPresenceSub = receiveNotification(.receivedMessage)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let message = notification.object as! RelayMessage
                guard let event = message.event else { return }
                guard event.kind == .custom(10312) else { return }
                
                let ago = Int(Date().timeIntervalSince1970 - (60 * 2)) // 2 min ago?
                guard event.createdAt.timestamp > ago else { return }
                
                guard event.tags.first(where: { $0.type == "a" && $0.value == self.id }) != nil else { return }
                

                guard !self.participantsOrSpeakers.contains(where: { $0.pubkey == event.publicKey }) else { return }
                if !self.othersPresent.contains(event.publicKey) {
                    
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.othersPresent.insert(event.publicKey)
                    }
                    
                    bg().perform {
                        if let contact = Contact.fetchByPubkey(event.publicKey, context: bg()) {
                            let nrContact = NRContact(contact: contact)
                            DispatchQueue.main.async {
                                guard self.participantsOrSpeakers.first(where: { $0.pubkey == event.publicKey }) == nil else { return }
                                self.objectWillChange.send()
                                self.participantsOrSpeakers.append(nrContact)
                            }
                        }
                    }
                }
                
                if event.tags.first(where: { $0.type == "hand" && $0.value == "1" }) != nil {
                    DispatchQueue.main.async {
                        self.raisedHands.insert(event.publicKey)
                    }
                }
                else {
                    DispatchQueue.main.async {
                        self.raisedHands.remove(event.publicKey)
                    }
                }
            }
    }
    
    
    // Remove "expired" nrContacts from .othersPresent
    
    // Timer to refresh room presence (The presence event SHOULD be updated at regular intervals and clients SHOULD filter presence events older than a given time window.)
    private var timer: Timer?
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            let ago = Int(Date().timeIntervalSince1970 - (60 * 2)) // 2 min ago?
            
            
            let expiredNrContacts = self.participantsOrSpeakers.filter { nrContact in
                guard let presenceTimestamp = nrContact.presenceTimestamp else { return false }
                return presenceTimestamp < ago
            }
            if !expiredNrContacts.isEmpty {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.othersPresent = self.othersPresent.subtracting(expiredNrContacts.map { $0.pubkey })
                }
            }
        }
        timer?.tolerance = 5.0
    }
}

extension Event {
    
    func webUrl() -> String? {
        guard self.isLiveKit() else { return nil }
        guard let service = self.fastTags.first(where: { $0.0 == "service" })?.1 else { return nil }
        
        var relaysArray: [String] = []
        
        if let relays = self.fastTags.first(where: { $0.0 == "relays" }) {
            if let last = relays.3, let second = relays.2 {
                relaysArray = [relays.1, second, last]
            }
            else if let last = relays.2 {
                relaysArray = [relays.1, last]
            }
            else {
                relaysArray = [relays.1]
            }
        }
        
        guard let si = try? ShareableIdentifier(prefix: "naddr", kind: self.kind, pubkey: self.pubkey, dTag: self.dTag, relays: relaysArray) else { return nil }
        return (service + "/" + si.bech32string)
    }
    
    
    // If the room is a LiveKit room clients should auth with the service tag using NIP-98 auth at <service-url>/auth to obtain an access token.
    func liveKitAuthUrl() -> String? {
        guard self.isLiveKit() else { return nil }
        guard let service = self.fastTags.first(where: { $0.0 == "service" })?.1 else { return nil }
        return (service + "/api/v1/nests/auth")
    }
    
    func liveKitJoinUrl() -> String? {
        guard self.isLiveKit() else { return nil }
        guard let service = self.fastTags.first(where: { $0.0 == "service" })?.1 else { return nil }
        return (service + "/api/v1/nests/" + self.dTag)
    }
    
    func liveKitConnectUrl() -> String? {
        guard self.isLiveKit() else { return nil }
        guard let service = self.fastTags.first(where: { $0.0 == "service" })?.1 else { return nil }
        return service
    }
    
    func isLiveKit() -> Bool {
        return self.fastTags.contains(where: { $0.0 == "streaming" && $0.1.starts(with: "wss+livekit:") })
    }
    
    func streamingUrl() -> String? {
        guard isLiveKit() else { return nil }
        return self.fastTags.first(where: { $0.0 == "streaming" && $0.1.starts(with: "wss+livekit:") })?.1.replacingOccurrences(of: "s+livekit://", with: "s://")
    }
    
    func streamStatus() -> String? {
        return self.fastTags.first(where: { $0.0 == "status" })?.1
    }
    
    func isLive() -> Bool {
        return self.fastTags.contains(where: { $0.0 == "status" && $0.1 == "live" })
    }
    
    func isPlanned () -> Bool {
        return self.fastTags.contains(where: { $0.0 == "status" && $0.1 == "planned" })
    }
    
    func recordingUrl() -> String? {
        // Check if status is "ended" first
        guard self.fastTags.contains(where: { $0.0 == "status" && $0.1 == "ended" }) else { return nil }
        
        // return value "recording" tag
        return self.fastTags.first(where: { $0.0 == "recording" })?.1
    }
    
    func participantsOrSpeakers() -> [NRContact] {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        // Get author
        let author: NRContact? = if let contact = self.contact {
            NRContact(contact: contact)
        } else {
            nil
        }
        
        // Get participants, hosts, speakers
        var participantsOrSpeakers: [NRContact] = self.fastPs
            .filter { fastP in
                return (fastP.3?.lowercased() == "speaker" ||
                        fastP.3?.lowercased() == "host" ||
                        fastP.3?.lowercased() == "participant")
            }
            .map { $0.1 }
            .compactMap { pubkey in
                if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                    return NRContact(contact: contact)
                }
                return nil
            }
        
        if let author {
            participantsOrSpeakers.append(author)
        }
        
        return participantsOrSpeakers
    }
}
