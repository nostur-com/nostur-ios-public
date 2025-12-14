//
//  Utils.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/12/2025.
//

import Foundation
import Combine
import Playgrounds

class NXJob {
    public var subscriptions: Set<AnyCancellable> = []
    private let timeout: Double
    
    init(timeout: Double = 5.0, setup: @escaping (NXJob) -> Void) {
        self.timeout = timeout
        setup(self)
    }
}

#Playground {
    
    let job = NXJob(timeout: 6.0) { job in
        MessageParser.shared.okSub
            .filter { $0.id == "2" }
            .sink { message in
                print("message.id: \(message.id) message.relayId: \(message.relay)")
            }
            .store(in: &job.subscriptions)
    }
    
    
    MessageParser.shared.okSub.send((id: "1", relay: "test"))
    MessageParser.shared.okSub.send((id: "2", relay: "test"))
    MessageParser.shared.okSub.send((id: "3", relay: "test"))
    
}
