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
            if oldValue != nil && activeNest != oldValue {
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
    
    @Published public var state: LiveKitVoiceSessionState = .disconnected {
        didSet {
            if case .connecting = state { }
            else { activeNest?.joining = false }
        }
    }
    
    @Published public var isRecording: Bool = false
    
    @Published public var listenAnonymously: Bool = false
    
    public let anonymousKeys = try! Keys.newKeys()
    public var anonymousPubkeyCached = ""
    
    static let shared = LiveKitVoiceSession()
    
    private init() { }
    
    lazy var room = Room(delegate: self)
    
    public var currentRoomATag: String? {
        nrLiveEvent?.id
    }

    var tracks: [Track] = []
    
    public var accountType: NestAccountType?

    private var nrLiveEvent: NRLiveEvent? = nil
    
    @MainActor
    func connect(_ url: String, token: String, accountType: NestAccountType, nrLiveEvent: NRLiveEvent, completion: (() -> Void)? = nil) {
        self.anonymousPubkeyCached = anonymousKeys.publicKeyHex
        self.state = .connecting
//        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        self.nrLiveEvent = nrLiveEvent
        self.accountType = accountType
        self.isRecording = false
        
        Task {
           do {
               try await room.connect(url: url, token: token)
               // Publish mic only
               try await room.localParticipant.setCamera(enabled: false)
               try await room.localParticipant.setMicrophone(enabled: !self.isMuted)
               self.state = .connected
               completion?()
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
        self.accountType = nil
        self.isRecording = false
        Task {
            await room.disconnect()
       }
    }
    
    func broadCastRoomPresence(raisedHand: Bool = false) { // TODO: broadcast to? own relay set? nest preferred relays? outbox? or? hmm

        guard let currentRoomATag = self.currentRoomATag else { return }
        
        var presenceEvent = NEvent(content: "")
        presenceEvent.kind = .custom(10312)
        presenceEvent.tags.append(NostrTag(["a", currentRoomATag]))
        
        if raisedHand {
            presenceEvent.tags.append(NostrTag(["hand", "1"]))
        }
        
        switch accountType {
        case .account(let cloudAccount):
            nrLiveEvent?.participantsOrSpeakers.first(where: { $0.pubkey == cloudAccount.publicKey })?.raisedHand = raisedHand
            presenceEvent.publicKey = cloudAccount.publicKey
            
            if cloudAccount.isNC {
                presenceEvent = presenceEvent.withId()
                NSecBunkerManager.shared.requestSignature(forEvent: presenceEvent, usingAccount: cloudAccount, whenSigned: { signedPresenceEvent in
                    Unpublisher.shared.publishNow(signedPresenceEvent, skipDB: true)
                })
            }
            else {
                guard let signedPresenceEvent = try? cloudAccount.signEvent(presenceEvent) else { return }
                Unpublisher.shared.publishNow(signedPresenceEvent, skipDB: true)
            }
            
        case .anonymous(let nKeys):
            presenceEvent.publicKey = nKeys.publicKeyHex
            nrLiveEvent?.participantsOrSpeakers.first(where: { $0.pubkey == presenceEvent.publicKey })?.raisedHand = raisedHand
            guard let signedPresenceEvent = try? presenceEvent.sign(nKeys) else { return }
            Unpublisher.shared.publishNow(signedPresenceEvent, skipDB: true)

        case nil:
            return
        }
 
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
            Task { @MainActor in
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
        guard timer == nil else { return }
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
                    // If our account is moved on stage while we had raised hand, lower hand.
                    if (self.raisedHand) {
                        if case .account(let account) = self.accountType, account.publicKey == participantPubkey {
                            self.lowerHand()
                        }
                        else if case .anonymous(let keys) = self.accountType, keys.publicKeyHex == participantPubkey {
                            self.lowerHand()
                        }
                    }
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
                let nrContact = NRContact.instance(of: participantPubkey)
                
                let isMuted = if let audioPublication = participant.firstAudioPublication, audioPublication.isMuted {
                    true
                }
                else {
                    false
                }
                
                if nrContact.pubkey == self.anonymousPubkeyCached {
                    DispatchQueue.main.async {
                        nrContact.anyName = "You"
                        nrContact.isMuted = isMuted
                    }
                }

                DispatchQueue.main.async {
                    guard let nrLiveEvent = self.nrLiveEvent else { return }
                    nrLiveEvent.objectWillChange.send()
                    if !nrLiveEvent.participantsOrSpeakers.contains(where: { $0.pubkey == nrContact.pubkey } ) {
                        nrLiveEvent.participantsOrSpeakers.append(nrContact)
                    }
                }
                
                if nrContact.metadata_created_at == 0 {
                    QueuedFetcher.shared.enqueue(pTag: participantPubkey)
                }
            }
        }

    }
}


extension LiveKitVoiceSession: RoomDelegate {
    
    func roomDidConnect(_ room: Room) {
        L.nests.debug("roomDidConnect: participantCount: \(room.participantCount.description)")
        
        self.syncParticipants()
        self.syncRoomMetadata(metadata: room.metadata)
        
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
            self.isRecording = room.isRecording
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
    
    /// ``Room/metadata`` has updated.
    func room(_ room: Room, didUpdateMetadata metadata: String?) {
        L.nests.debug("room: didUpdateMetadata: metadata \(metadata ?? "")")
        self.syncRoomMetadata(metadata: metadata)
    }
    
    private func syncRoomMetadata(metadata: String?) {
        guard let metadataString = metadata else { return }
        let decoder = JSONDecoder()
        guard let dataFromString = metadataString.data(using: .utf8, allowLossyConversion: false), let lkMetadata = try? decoder.decode(LiveKitRoomMetaData.self, from: dataFromString) else {
            return
        }
        Task { @MainActor in
            // Remove from stage
            let beforeOnStage = nrLiveEvent?.pubkeysOnStage ?? []
            let noLongerOnStage = beforeOnStage.subtracting(Set(lkMetadata.speakers)) // diff
            nrLiveEvent?.othersPresent = (nrLiveEvent?.othersPresent ?? []).union(noLongerOnStage) // put what is removed back to .othersPresent (listening)
            
            // Add to stage
            nrLiveEvent?.pubkeysOnStage = Set(lkMetadata.speakers)
            nrLiveEvent?.othersPresent.subtract(Set(lkMetadata.speakers)) // remove from listening
            
            nrLiveEvent?.admins = if let host = lkMetadata.host {
                Set(lkMetadata.admins + [host])
            }
            else {
                Set(lkMetadata.admins)
            }
            isRecording = lkMetadata.recording
        }
    }
    
    /// ``TrackPublication/isMuted`` has updated.
    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        guard let participantPubkey = participant.identity?.stringValue else { return }
        guard isValidPubkey(participantPubkey) else { return }
        
        if let nrContact = self.nrLiveEvent?.participantsOrSpeakers.first(where: { $0.pubkey == participantPubkey }) {
            Task { @MainActor in
                withAnimation {
                    nrContact.volume = isMuted ? 0 : CGFloat(participant.audioLevel)
                    nrContact.isMuted = isMuted
                }
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

enum NestAccountType {
    case account(CloudAccount)
    case anonymous(Keys)
}
