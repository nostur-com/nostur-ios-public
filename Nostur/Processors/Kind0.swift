//
//  Kind0.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/10/2023.
//

import Foundation
import Combine

class Kind0Processor {
    
    static let shared = Kind0Processor()

    public var queue = DispatchQueue(label: "kind0-processor", qos: .utility, attributes: .concurrent)
    public var request = PassthroughSubject<Pubkey, Never>()
    public var receive = PassthroughSubject<Profile, Never>()
    
    private init() {
        setupProcessors()
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    // Don't access directly, use get/setProfile which goes through own queue
    private var _lru = [Pubkey: Profile]() // TODO: Turn into real LRU
    
    private func getProfile(_ pubkey: String) async -> Profile? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self._lru[pubkey])
            }
        }
    }
    
    private func setProfile(_ profile: Profile) {
        queue.async(flags: .barrier) { [weak self] in
            self?._lru[profile.pubkey] = profile
        }
    }
    
    private func setupProcessors() {
        request
            // TODO: Add throttle and batching
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .sink { [weak self] pubkey in
                // check LRU
                Task { [weak self] in
                    guard let self else { return }
                    if let profile = await self.getProfile(pubkey) {
                        self.receive.send(profile)
                        return
                    }
                    
                    // check DB
                    await bg().perform { [weak self] in
                        guard let self else { return }
                        if let profile = self.fetchProfile(pubkey: pubkey) {
                            self.receive.send(profile)
                            self.setProfile(profile)
                        }
                        else {
                            // req relay
                            req(RM.getUserMetadata(pubkey: pubkey))
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
        receive
            .subscribe(on: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .sink { [weak self] profile in
                self?.setProfile(profile)
                if let cachedNRContact = NRContactCache.shared.retrieveObject(at: profile.pubkey) {
                    DispatchQueue.main.async {
                        cachedNRContact.anyName = profile.name
                        cachedNRContact.pictureUrl = profile.pictureUrl
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func fetchProfile(pubkey: Pubkey) -> Profile? {
        guard let contact = Contact.fetchByPubkey(pubkey, context: bg())
        else { return nil }
        return Profile(pubkey: pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl)
    }
}

struct Profile {
    let pubkey: String
    let name: String
    var pictureUrl: URL?
}
