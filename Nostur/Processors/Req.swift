//
//  Req.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/10/2023.
//

import Foundation
import Combine
import NostrEssentials

class ReqProcessor {
    
    static let shared = ReqProcessor()

    public var queue = DispatchQueue(label: "req-processor", qos: .utility, attributes: .concurrent)
    public var requestP = PassthroughSubject<Pubkey, Never>()
    public var requestId = PassthroughSubject<PostID, Never>()
    
    private let fastLane = PassthroughSubject<Pubkey, Never>()
    private let slowLane = PassthroughSubject<Pubkey, Never>()
    
    private var fastLaneAvailable = true
    private var slowLaneAvailable = true
    
    static let FASTLANE_COLLECT_TIME = 0.05
    static let SLOWLANE_COLLECT_TIME = 1.5
    
    private init() {
        setupProcessors()
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    private func setupProcessors() {

        // Fast lane
        fastLane
            .collect(.byTime(DispatchQueue.global(), .milliseconds(Int(Self.FASTLANE_COLLECT_TIME * 1000))))
            .filter { !$0.isEmpty }
            .sink { pubkeys in
                print("Fast lane request for IDs: \(pubkeys)")
//                let filter1 = Filters(authors: pubkeys, kinds: [0])
//                let filter2 = Filters(kinds:[9735], limit: 200)
//                
//                let requestMessage = ClientMessage(type:.REQ, subscriptionId:"multitest", filters: [filter1,filter2])
//                req()
                self.fastLaneAvailable = false
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.FASTLANE_COLLECT_TIME) {
                    self.fastLaneAvailable = true
                }
            }
            .store(in: &subscriptions)

        // Slow lane
        slowLane
            .collect(.byTime(DispatchQueue.global(), .seconds(Self.SLOWLANE_COLLECT_TIME)))
            .filter { !$0.isEmpty }
            .sink { pubkeys in
                print("Slow lane request for IDs: \(pubkeys)")
                self.slowLaneAvailable = false
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.SLOWLANE_COLLECT_TIME) {
                    self.slowLaneAvailable = true
                }
            }
            .store(in: &subscriptions)

        requestP
            .sink { pubkey in
                if self.fastLaneAvailable && self.slowLaneAvailable {
                    self.fastLane.send(pubkey)
                } else {
                    self.slowLaneAvailable = false
                    self.slowLane.send(pubkey)
                }
            }
            .store(in: &subscriptions)
    }
}
