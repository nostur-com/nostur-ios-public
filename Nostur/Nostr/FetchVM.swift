//
//  FetchVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

// Generic reusable fetcher
class FetchVM<T: Equatable>: ObservableObject {
    
    public typealias FetchParams = (prio: Bool?, req: (String) -> Void, onComplete: (NXRelayMessage?, Event?) -> Void, altReq: ((String) -> Void)?)
    
    @Published var state: State
    private let backlog: Backlog
    private let debounceTime: Double
    private var fetchParams: FetchParams? = nil
    
    init(timeout: Double = 4.0, debounceTime: Double = 0.25) {
        self.state = .initializing
        self.debounceTime = debounceTime
        self.backlog = Backlog(timeout: timeout, auto: true, backlogDebugName: "FetchVM")
    }
    
    public func setFetchParams(_ fetchParams: FetchParams) {
        self.fetchParams = fetchParams
    }
    
    public func ready(_ item: T) {
        DispatchQueue.main.async { [weak self] in
            self?.backlog.clear()
            self?.state = .ready(item)
        }
    }

    public func altFetch() {
        guard let _fetchParams = self.fetchParams else { L.og.error("🔴🔴 FetchVM: missing fetchParams"); return }
        guard let _altReq = _fetchParams.altReq else { L.og.error("🔴🔴 FetchVM: missing fetchParams.altReq"); return }
        let reqTask = ReqTask(
            prio: _fetchParams.prio ?? false,
            debounceTime: self.debounceTime,
            reqCommand: { [weak self] taskId in
                DispatchQueue.main.async {
                    self?.state = .altLoading
                }
                _altReq(taskId)
            },
            processResponseCommand: { [weak self] taskId, relayMessage, event in
#if DEBUG
                L.og.info("FetchVM: ready to process relay response - \(taskId)")
#endif
                _fetchParams.onComplete(relayMessage, event)
                self?.backlog.clear()
            },
            timeoutCommand: { [weak self] taskId in
#if DEBUG
                L.og.info("FetchVM: timeout (altFetch)- \(taskId)")
#endif
                _fetchParams.onComplete(nil, nil)
                self?.backlog.clear()
            })

        self.backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func timeout() {
        DispatchQueue.main.async { [weak self] in
            self?.state = .timeout
        }
    }
    
    public func error(_ text:String) {
        DispatchQueue.main.async { [weak self] in
            self?.state = .error(text)
        }
    }
    
    public func fetch() {
        guard let _fetchParams = self.fetchParams else { L.og.error("🔴🔴 FetchVM: missing fetchParams"); return }
        let reqTask = ReqTask(
            prio: _fetchParams.prio ?? false,
            debounceTime: self.debounceTime,
            reqCommand: { taskId in
                _fetchParams.req(taskId)
            },
            processResponseCommand: { [weak self] taskId, relayMessage, event in
#if DEBUG
                L.og.info("FetchVM: ready to process relay response - \(taskId)")
#endif
                _fetchParams.onComplete(relayMessage, event)
                self?.backlog.clear()
            },
            timeoutCommand: { [weak self] taskId in
#if DEBUG
                L.og.info("FetchVM: timeout (fetch) - \(taskId)")
#endif
                self?.backlog.clear()
                _fetchParams.onComplete(nil, nil)
            })

        self.backlog.add(reqTask)
        reqTask.fetch()
    }
    
    enum State: Equatable {
        case initializing
        case loading
        case altLoading
        case ready(T)
        case timeout
        case error(String)
    }
}
