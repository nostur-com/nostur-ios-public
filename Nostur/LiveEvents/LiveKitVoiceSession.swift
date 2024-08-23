//
//  LiveKitVoiceSession.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/07/2024.
//

import SwiftUI
import LiveKit
import AVFoundation
import NostrEssentials

class LiveKitVoiceSession: ObservableObject {
    
    @Published public var activeNest: NRLiveEvent? = nil {
        didSet {
            if activeNest != oldValue {
                Task { @MainActor in
                    self.disconnect()
                }
            }
            else {
                visibleNest = activeNest
            }
        }
    }
    
    @Published public var visibleNest: NRLiveEvent? = nil
    
    @Published public var state: LiveKitVoiceSessionState = .disconnected
    
    @Published public var isRecording: Bool = false
    
    static let shared = LiveKitVoiceSession()
    
    private init() { }
    
    lazy var room = Room(delegate: self)
    
    private var currentRoomATag: String? {
        nrLiveEvent?.id
    }

    var tracks: [Track] = []
    
    // own most recent presence id, delete on disconnect?
    private var accountPubkey: String?
    private var ownPresenceId: String?
    
    private var nrLiveEvent: NRLiveEvent? = nil
    
    @MainActor
    func connect(_ url: String, token: String, accountPubkey: String, nrLiveEvent: NRLiveEvent) {
        self.state = .connecting
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .duckOthers)
        self.nrLiveEvent = nrLiveEvent
        self.accountPubkey = accountPubkey
        
        Task {
           do {
               try await room.connect(url: url, token: token)
               // Publish mic only
               try await room.localParticipant.setCamera(enabled: false)
               try await room.localParticipant.setMicrophone(enabled: !self.isMuted)
               self.state = .connected
           } catch {
               L.nests.debug("Failed to connect: \(error)")
               self.state = .error(error.localizedDescription)
           }
       }
    }
    
    @MainActor
    func disconnect() {
        self.state = .disconnected
        self.nrLiveEvent = nil
        self.accountPubkey = nil
        Task {
            await room.disconnect()
       }
    }
    
    func uuuh() {
        Task {
           do {
               try await room.localParticipant.setMicrophone(enabled: true)
           } catch {
               L.nests.debug("Failed to uuhhh: \(error)")
           }
       }
    }
    
    func broadCastRoomPresence(raisedHand: Bool = false) { // TODO: broadcast to? own relay set? nest preferred relays? outbox? or? hmm
        guard let accountPubkey = self.accountPubkey else { return }
        guard let account = account(), account.publicKey == accountPubkey else { return }
        guard let currentRoomATag = self.currentRoomATag else { return }
        
        var presenceEvent = NEvent(content: "")
        presenceEvent.kind = .custom(10312)
        presenceEvent.tags.append(NostrTag(["a", currentRoomATag]))
        
        if raisedHand {
            presenceEvent.tags.append(NostrTag(["hand", "1"]))
        }
        
        guard let signedPresenceEvent = try? account.signEvent(presenceEvent) else { return }
        
        
        // TODO: BUNKER HANDLING
        ConnectionPool.shared.sendMessage(
            NosturClientMessage(
                clientMessage: NostrEssentials.ClientMessage(type: .EVENT, event: signedPresenceEvent.toNostrEssentialsEvent()),
                relayType: .WRITE
            ),
            accountPubkey: signedPresenceEvent.publicKey
        )        
    }
    
    // shortcut functions for convenience
    @MainActor
    func raiseHand() {
        self.raisedHand = true
    }
    
    @MainActor
    func lowerHand() {
        self.raisedHand = false
    }
    
    // need to store it for room presence refresh (and also view state)
    @Published public var raisedHand: Bool = false {
        didSet {
            self.broadCastRoomPresence(raisedHand: raisedHand)
        }
    }

    @Published public var isMuted: Bool = true {
        didSet {
            Task {
                guard room.connectionState == .connected else { return }
                do {
                    try await room.localParticipant.setMicrophone(enabled: !isMuted)
                }
                catch {
                    L.nests.debug("Failed to mute/unmute: \(error)")
                    isMuted = false
                }
            }
        }
    }
    
    @MainActor
    func mute() {
        isMuted = true
    }
    
    func unmute() {
        isMuted = false
    }
    
    // Timer to refresh room presence (The presence event SHOULD be updated at regular intervals and clients SHOULD filter presence events older than a given time window.)
    private var timer: Timer?
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            Task { @MainActor in
                self.broadCastRoomPresence(raisedHand: self.raisedHand)
            }
        }
        timer?.tolerance = 5.0
    }
    
    
    private func syncParticipants() {
        
        let ctx = bg()
        
        for participant in room.allParticipants.values {
            guard let participantPubkey = participant.identity?.stringValue else { return }
            guard isValidPubkey(participantPubkey) else { continue }
            
            if participant.permissions.canPublish {
                DispatchQueue.main.async {
                    self.nrLiveEvent?.objectWillChange.send()
                    self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
                    self.nrLiveEvent?.othersPresent.remove(participantPubkey)
                    if let audioPublication = participant.firstAudioPublication, audioPublication.isMuted {
                        self.nrLiveEvent?.mutedPubkeys.insert(participantPubkey)
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    self.nrLiveEvent?.objectWillChange.send()
                    self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
                    self.nrLiveEvent?.othersPresent.insert(participantPubkey)
                    self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
                }
            }
            
            guard self.nrLiveEvent?.participantsOrSpeakers.first(where: { $0.pubkey == participantPubkey }) == nil else { continue }
            
            ctx.perform { [weak self] in
                guard let self else { return }
                if let contact = Contact.fetchByPubkey(participantPubkey, context: ctx) {
                    let nrContact = NRContact(contact: contact)
                    nrContact.isMuted = if let audioPublication = participant.firstAudioPublication, audioPublication.isMuted {
                        true
                    }
                    else {
                        false
                    }

                    DispatchQueue.main.async {
                        self.nrLiveEvent?.objectWillChange.send()
                        self.nrLiveEvent?.participantsOrSpeakers.append(nrContact)
                    }
                }
                else {
                    let contact = Contact(context: ctx)
                    contact.pubkey = participantPubkey
                    contact.metadata_created_at = 0
                    contact.updated_at = Int64(Date.now.timeIntervalSince1970) // by Nostur
                    
                    EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "syncParticipants.001")
                    QueuedFetcher.shared.enqueue(pTag: participantPubkey)
                    
                    let nrContact = NRContact(contact: contact)
                    nrContact.isMuted = if let audioPublication = participant.firstAudioPublication, audioPublication.isMuted {
                        true
                    }
                    else {
                        false
                    }
                    DispatchQueue.main.async {
                        self.nrLiveEvent?.objectWillChange.send()
                        self.nrLiveEvent?.participantsOrSpeakers.append(nrContact)
                    }
                    bgSave()
                }
            }
        }

    }
}


extension LiveKitVoiceSession: RoomDelegate {
    
    func roomDidConnect(_ room: Room) {
        L.nests.debug("roomDidConnect: participantCount: \(room.participantCount.description)")
        
        self.syncParticipants()
        
        Task { @MainActor in
            self.isRecording = room.isRecording
            self.state = .connected
            // Broadcast room presence
            self.broadCastRoomPresence()
        }
    }
    
    // A ``RemoteParticipant`` joined the room.
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        L.nests.debug("room: participantDidConnect: participant.name \(participant.name ?? "")")
        self.syncParticipants()
    }
    
    // A ``RemoteParticipant`` left the room.
    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        L.nests.debug("room: participantDidDisconnect: participant.name \(participant.name ?? "")")
        
        guard let participantPubkey = participant.identity?.stringValue else { return }
        guard isValidPubkey(participantPubkey) else { return }
        
        DispatchQueue.main.async {
            self.nrLiveEvent?.objectWillChange.send()
            self.nrLiveEvent?.participantsOrSpeakers.removeAll(where: { $0.pubkey == participantPubkey })
            self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
            self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
            self.nrLiveEvent?.othersPresent.remove(participantPubkey)
        }
    }
    
    // Speakers in the room has updated.
    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        L.nests.debug("participant: didUpdateSpeakingParticipants: participants.count \(participants.count.description)")
        for participant in participants {
            L.nests.debug("participant audio level: \(participant.audioLevel.description)")
            L.nests.debug("participant firstAudioPublication?.isMuted: \((participant.firstAudioPublication?.isMuted ?? false).description)")
            
            guard let participantPubkey = participant.identity?.stringValue else { continue }
            guard isValidPubkey(participantPubkey) else { continue }
            
            if let nrContact = self.nrLiveEvent?.participantsOrSpeakers.first(where: { $0.pubkey == participantPubkey }) {
                Task { @MainActor in
                    withAnimation {
                        nrContact.volume = CGFloat(participant.audioLevel)
                        nrContact.isMuted = participant.firstAudioPublication?.isMuted ?? false
                    }
                }
            }
        }
    }
    
    // A ``RemoteParticipant`` has published a ``RemoteTrack``. (ADDED TO STAGE)
    func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        L.nests.debug("participant: didPublishTrack: publication.track?.id \(publication.track?.id ?? "" )")
        
//        guard let participantPubkey = participant.identity?.stringValue else { return }
//        guard isValidPubkey(participantPubkey) else { return }
//        
//        DispatchQueue.main.async {
//            self.nrLiveEvent?.objectWillChange.send()
//            
//            if participant.permissions.canPublish {
//                self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
//                self.nrLiveEvent?.othersPresent.remove(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
//                self.nrLiveEvent?.othersPresent.insert(participantPubkey)
//            }
//            
//            if publication.isMuted {
//                self.nrLiveEvent?.mutedPubkeys.insert(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
//            }
//        }
    }
    
    // A ``RemoteParticipant`` has un-published a ``RemoteTrack``. (REMOVED FROM STAGE)
    func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) {
        L.nests.debug("participant: didUnpublishTrack: publication.track?.id \(publication.track?.id ?? "" )")
        
//        guard let participantPubkey = participant.identity?.stringValue else { return }
//        guard isValidPubkey(participantPubkey) else { return }
//        
//        DispatchQueue.main.async {
//            self.nrLiveEvent?.objectWillChange.send()
//            if participant.permissions.canPublish {
//                self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
//                self.nrLiveEvent?.othersPresent.remove(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
//                self.nrLiveEvent?.othersPresent.insert(participantPubkey)
//            }
//            if publication.isMuted {
//                self.nrLiveEvent?.mutedPubkeys.insert(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
//            }
//        }
    }

    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard let track = publication.track as? AudioTrack else { return }
        
        L.nests.debug("participant: LocalParticipant didPublishTrack: publication.track?.id \(publication.track?.id ?? "" )")
//        
//        guard let participantPubkey = participant.identity?.stringValue else { return }
//        guard isValidPubkey(participantPubkey) else { return }
        
//        DispatchQueue.main.async {
//            self.nrLiveEvent?.objectWillChange.send()
//            if participant.permissions.canPublish {
//                self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
//                self.nrLiveEvent?.othersPresent.remove(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
//                self.nrLiveEvent?.othersPresent.insert(participantPubkey)
//            }
//            if publication.isMuted {
//                self.nrLiveEvent?.mutedPubkeys.insert(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
//            }
//        }
        
        DispatchQueue.main.async {
            self.tracks.append(track)
        }
    }

//    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
//        
//    }
    
    // The ``LocalParticipant`` has un-published a ``LocalTrack``.
    func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        guard let track = publication.track as? AudioTrack else { return }
        
        L.nests.debug("participant: LocalParticipant didUnpublishTrack: publication.track?.id \(publication.track?.id ?? "" )")
        
//        guard let participantPubkey = participant.identity?.stringValue else { return }
//        guard isValidPubkey(participantPubkey) else { return }
//        
//        DispatchQueue.main.async {
//            self.nrLiveEvent?.objectWillChange.send()
//            if participant.permissions.canPublish {
//                self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
//                self.nrLiveEvent?.othersPresent.remove(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
//                self.nrLiveEvent?.othersPresent.insert(participantPubkey)
//            }
//            if publication.isMuted {
//                self.nrLiveEvent?.mutedPubkeys.insert(participantPubkey)
//            }
//            else {
//                self.nrLiveEvent?.mutedPubkeys.remove(participantPubkey)
//            }
//        }
        
        DispatchQueue.main.async {
            self.tracks.removeAll(where: { $0 == track })
        }
    }
    
    // On/off stage by canPublish permissions:
    // ``Participant/permissions`` has updated.
    func room(_ room: Room, participant: Participant, didUpdatePermissions permissions: ParticipantPermissions) {
        L.nests.debug("participant: didUpdatePermissions: permissions \(permissions.description)")
        
        guard let participantPubkey = participant.identity?.stringValue else { return }
        guard isValidPubkey(participantPubkey) else { return }
        
        DispatchQueue.main.async {
            self.nrLiveEvent?.objectWillChange.send()
            if participant.permissions.canPublish {
                self.nrLiveEvent?.pubkeysOnStage.insert(participantPubkey)
                self.nrLiveEvent?.othersPresent.remove(participantPubkey)
            }
            else {
                self.nrLiveEvent?.pubkeysOnStage.remove(participantPubkey)
                self.nrLiveEvent?.othersPresent.insert(participantPubkey)
            }
        }
    }
    
    // ``Participant/metadata`` has updated.
    func room(_ room: Room, participant: Participant, didUpdateMetadata metadata: String?) {
        L.nests.debug("room: didUpdateMetadata: metadata \(metadata ?? "")")
    }

    // ``Participant/name`` has updated.
    func room(_ room: Room, participant: Participant, didUpdateName name: String) {
        L.nests.debug("room: didUpdateName: name \(name)")
    }
    
    // Could not connect to the room. Only triggered when the initial connect attempt fails.
    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        L.nests.debug("didFailToConnectWithError: error \(error?.localizedDescription ?? "")")
        Task { @MainActor in
            self.state = .error(error?.localizedDescription ?? "Error")
        }
    }
    
    /// ``Room/isRecording`` has updated.
    func room(_ room: Room, didUpdateIsRecording isRecording: Bool) {
        if isRecording != self.isRecording {
            Task { @MainActor in
                self.isRecording = isRecording
            }
        }
    }

}

enum LiveKitVoiceSessionState {
    case connecting
    case connected
    case disconnected
    case error(String)
}
