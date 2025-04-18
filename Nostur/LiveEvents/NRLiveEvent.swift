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
    public var liveKitBaseUrl: String?
    public var streamingUrl: String?
    public var webUrl: String?
    public var isLiveKit: Bool = false
    @Published public var status: String? {
        didSet {
            if status == "live" {
                Task { @MainActor in
                    LiveEventsModel.shared.livePubkeys = LiveEventsModel.shared.livePubkeys.union(Set(self.participantsOrSpeakers.map { $0.pubkey } + [self.pubkey]))
                }
            }
        }
    }
    @Published public var scheduledAt: Date?
    
    public var streamHasEnded: Bool {
        if let status, status == "ended" {
            return true
        }
        return false
    }
    
    public var recordingUrl: String?
    public var liveKitConnectUrl: String?
    
    // LiveKit auth token
    @Published public var authToken: String?
    
    private let backlog = Backlog(auto: true)
    private var listenForPresenceSub: AnyCancellable?
    
    public var nEvent: NEvent
    
    @Published public var chatVM = ChatRoomViewModel()
    @Published var joining = false
    
    var isNSFW: Bool = false
    
    init(event: Event) {
        self.nEvent = event.toNEvent() // TODO: This is NEvent (MessageParser) to Event (Importer) back to NEvent (here), need to fix better
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
        self.liveKitBaseUrl = event.liveKitBaseUrl()
        self.streamingUrl = event.streamingUrl()
        self.isLiveKit = event.isLiveKit()
        self.webUrl = event.webUrl()
        self.status = event.streamStatus()
        self.recordingUrl = event.recordingUrl()
        self.liveKitConnectUrl = event.liveKitConnectUrl()
        
        self.pubkeysOnStage.formUnion(Set(event.participantsOrSpeakers().map { $0.pubkey }))
        self.pubkeysOnStage.insert(event.pubkey)
        
        self.scheduledAt = if event.isPlanned(),
                                        let startsTag = event.fastTags.first(where: { $0.0 == "starts" }),
                                        let starts = Double(startsTag.1) {
            Date(timeIntervalSince1970: starts)
        }
        else {
            nil
        }
        self.isNSFW = self.hasNSFWContent()
    }
    
    private func hasNSFWContent() -> Bool {
        return nEvent.fastTags.contains(where: { tag in
            // contains nsfw hashtag?
            tag.0 == "t" && tag.1.lowercased() == "nsfw" ||
            // contains content-warning tag
            tag.0 == "content-warning"
        })
        // TODO: check labels/reports
    }
    
    public func loadReplacableData(_ params: (nEvent: NEvent,
                                              participantsOrSpeakers: [NRContact],
                                              title: String?,
                                              summary: String?,
                                              fastPs: [FastTag],
                                              totalParticipants: Int,
                                              url: URL?,
                                              eventJson: String,
                                              liveKitJoinUrl: String?,
                                              streamingUrl: String?,
                                              webUrl: String?,
                                              thumbUrl: String?,
                                              streamStatus: String?,
                                              recordingUrl: String?,
                                              liveKitBaseUrl: String?,
                                              liveKitConnectUrl: String?,
                                              scheduledAt: Date?
                                             )) {
        
        self.objectWillChange.send()
        self.nEvent = params.nEvent
        self.participantsOrSpeakers = params.participantsOrSpeakers
        self.pubkeysOnStage.formUnion(Set(params.participantsOrSpeakers.map { $0.pubkey }))
        self.fastPs = params.fastPs
        self.totalParticipants = params.totalParticipants
        self.title = params.title
        self.summary = params.summary
        self.url = params.url
        self.eventJson = params.eventJson
        self.liveKitJoinUrl = params.liveKitJoinUrl
        self.liveKitBaseUrl = params.liveKitBaseUrl
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
        if self.pubkey == pubkey {
            return String(localized: "Host", comment: "Role of participant")
        }
        if admins.contains(pubkey) {
            return String(localized: "Moderator", comment: "Role of participant")
        }
        if onStage.contains(where: { $0.pubkey == pubkey }) {
            return String(localized: "Speaker", comment: "Role of participant")
        }
        return fastPs.first(where: { $0.1 == pubkey })?.3?.capitalized
    }
    
    @MainActor
    public func joinRoom(account: CloudAccount, completion: ((String) -> Void)? = nil) {
        joining = true
        guard let liveKitJoinUrl = self.liveKitJoinUrl else { return }
        
        var nEvent = NEvent(content: "")
        nEvent.publicKey = account.publicKey
        nEvent.kind = .custom(27235)
        nEvent.tags.append(NostrTag(["u", liveKitJoinUrl]))
        nEvent.tags.append(NostrTag(["method", "GET"]))
        
        if account.isNC {
            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { [weak self] signedNip98Event in
     
                let jsonString = signedNip98Event.eventJson()
                guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else { return }
                let base64 = jsonData.base64EncodedString()
                let authorizationHeader = "Nostr \(base64)"
                
                Task {
                    do {
                        guard let self else { return }
                        let jsonResponse = try await self.fetchData(from: liveKitJoinUrl, authHeader: authorizationHeader)
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
            })
        }
        else {
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
    }
    
    @MainActor
    public func joinRoomAnonymously(keys: Keys, completion: ((String) -> Void)? = nil) {
        joining = true
        guard let liveKitJoinUrl = self.liveKitJoinUrl else { return }
        
        var nEvent = NEvent(content: "")
        nEvent.publicKey = keys.publicKeyHex
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
        let ago = Int(Date().timeIntervalSince1970 - 120) // 2 min ago?
        
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
    @Published public var admins: Set<String> = []
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
                
                let ago = Int(Date().timeIntervalSince1970 - 120) // 2 min ago?
                guard event.createdAt.timestamp > ago else { return }
                
                guard event.tags.first(where: { $0.type == "a" && $0.value == self.id }) != nil else { return }
                

                guard !self.participantsOrSpeakers.contains(where: { $0.pubkey == event.publicKey }) else { return }
                if !self.othersPresent.contains(event.publicKey) {
                    
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                        self.othersPresent.insert(event.publicKey)
                    }
                    
                    bg().perform {
                        if let nrContact = NRContact.fetch(event.publicKey, context: bg()) {
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
            let ago = Int(Date().timeIntervalSince1970 - 120) // 2 min ago?
            
            
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
    
    @MainActor
    public func goLive(account: CloudAccount) {
        guard account.publicKey == self.pubkey else { return }
        
        var nEvent = self.nEvent
        nEvent.createdAt = NTimestamp(date: .now)
        nEvent.tags = nEvent.tags.compactMap { tag in
            if tag.type == "status" {
                return NostrTag(["status", "live"])
            }
            return tag
        }
        if account.isNC {
            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account) { signedNEvent in
                Unpublisher.shared.publishNow(signedNEvent, skipDB: true)
                MessageParser.shared.handleNormalMessage(message: RelayMessage(relays: "local", type: .EVENT, message: "", event: signedNEvent), nEvent: signedNEvent, relayUrl: "local")
                self.status = "live"
            }
        }
        else {
            if let signedNEvent = try? account.signEvent(nEvent) {
                Unpublisher.shared.publishNow(signedNEvent, skipDB: true)
                MessageParser.shared.handleNormalMessage(message: RelayMessage(relays: "local", type: .EVENT, message: "", event: signedNEvent), nEvent: signedNEvent, relayUrl: "local")
                self.status = "live"
            }
        }
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
    
    func liveKitBaseUrl() -> String? {
        guard self.isLiveKit() else { return nil }
        guard let service = self.fastTags.first(where: { $0.0 == "service" })?.1 else { return nil }
        return service
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
            NRContact.fetch(contact.pubkey, contact: contact)
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
                return NRContact.fetch(pubkey)
            }
        
        if let author, !participantsOrSpeakers.contains(where: { $0.pubkey == author.pubkey }) {
            participantsOrSpeakers.append(author)
        }
        
        return participantsOrSpeakers
    }
}
