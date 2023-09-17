//
//  FetchVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

// Generic reusable fetcher
class FetchVM<T>: ObservableObject {
    
    public typealias FetchParams = (req: () -> Void, onComplete: (RelayMessage?) -> Void)
    
    @Published var state:State
    private let backlog:Backlog
    private let debounceTime:Double
    private var fetchParams: FetchParams? = nil
    
    init(timeout:Double = 5.0, debounceTime:Double = 0.5) {
        self.state = .initializing
        self.debounceTime = debounceTime
        self.backlog = Backlog(timeout: timeout, auto: true)
    }
    
    public func setFetchParams(_ fetchParams: FetchParams) {
        self.fetchParams = fetchParams
    }
    
    public func ready(_ item:T) {
        DispatchQueue.main.async {
            self.state = .ready(item)
        }
    }
    
    public func timeout() {
        DispatchQueue.main.async {
            self.state = .timeout
        }
    }
    
    public func fetch() {
        guard let fetchParams = self.fetchParams else { L.og.error("🔴🔴 FetchVM: missing fetchParams"); return }
        let reqTask = ReqTask(
            debounceTime: self.debounceTime,
            reqCommand: { taskId in
                fetchParams.req()
            },
            processResponseCommand: { taskId, relayMessage in
                L.og.info("FetchVM: ready to process relay response")
                fetchParams.onComplete(relayMessage)
                self.backlog.clear()
            },
            timeoutCommand: { taskId in
                L.og.info("FetchVM: timeout ")
                fetchParams.onComplete(nil)
                self.backlog.clear()
            })

        self.backlog.add(reqTask)
        reqTask.fetch()
    }
    
    enum State {
        case initializing
        case loading
        case ready(T)
        case timeout
    }
}
