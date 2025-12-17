//
//  Utils.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/12/2025.
//

import Foundation
import Combine
//import Playgrounds

class DMSendJob: Equatable {
    
    static func == (lhs: DMSendJob, rhs: DMSendJob) -> Bool {
        lhs.id == rhs.id
    }
    
    private var id: UUID
    public var subscriptions: Set<AnyCancellable> = []
    private let timeout: Double
    public var didSucceed = false
    private var onTimeout: (DMSendJob) -> Void
    private var onFinally: ((DMSendJob) -> Void)?
    private var timer: Timer? = nil
    
    init(timeout: Double = 5.0, setup: @escaping (DMSendJob) -> Void, onTimeout: @escaping (DMSendJob) -> Void, onFinally: ((DMSendJob) -> Void)? = nil) {
        self.id = UUID()
        self.timeout = timeout
        self.onTimeout = onTimeout
        self.onFinally = onFinally
        setup(self)
        self.timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self, !self.didSucceed else { return }
            self.onTimeout(self)
            self.onFinally?(self)
        }
    }
    
    public func onDidSucceed() {
        self.didSucceed = true
        self.timer?.invalidate()
        self.timer = nil
        self.onFinally?(self)
    }
}
//
//#Playground {
//    let job = NXJob(timeout: 6.0, setup: { job in
//        MessageParser.shared.okSub
//            .filter { $0.id == "2" }
//            .sink { message in
//                print("message.id: \(message.id) message.relayId: \(message.relay)")
//                job.onDidSucceed()
//            }
//            .store(in: &job.subscriptions)
//    }, onTimeout: { job in
//        print("timeout")
//    })
//    
//    MessageParser.shared.okSub.send((id: "1", relay: "test"))
//    MessageParser.shared.okSub.send((id: "2", relay: "test"))
//    MessageParser.shared.okSub.send((id: "3", relay: "test"))
//}


enum DMSendResult {
    case sending
    case success
    case timeout
}
