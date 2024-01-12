//
//  WebsiteComments.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/01/2024.
//

import SwiftUI
import NostrEssentials

class WebsiteCommentsViewModel: ObservableObject {
    
    @Published var state: State = .initializing
    
    private var backlog: Backlog = Backlog(timeout: 8.0, auto: true)
    
    // STEP 1: FETCH ALL KIND:443's for this URL
    private func fetchKind443sFromRelays(url: String, onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.1,
            reqCommand: { taskId in
                if let cm = NostrEssentials
                    .ClientMessage(
                        type: .REQ,
                        subscriptionId: taskId,
                        filters: [
                            Filters(
                                kinds: [443],
                                tagFilter: TagFilter(tag: "r", values: [url])
                            )
                        ]
                    ).json() {
                    req(cm)
                }
                else {
                    L.og.debug("Website Comments: Problem generating request")
                }
            },
            processResponseCommand: { taskId, relayMessage, _ in
                self.backlog.clear()
                self.fetchKind443sFromDb(url: url, onComplete: onComplete)
                
                L.og.debug("Website Comments: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.backlog.clear()
                self.fetchKind443sFromDb(url: url, onComplete: onComplete)
                L.og.debug("Website Comments: timeout ")
            })
        
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchKind443sFromDb(url: String, onComplete: (() -> ())? = nil) {
        
        bg().perform {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 443 AND tagsSerialized CONTAINS %@", ###"["r",""###)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            guard let events = try? bg().fetch(fr) else { return }
            
            let urlEvents = events.filter {  $0.fastTags.filter { $0.0 == "r" && $0.1 == url }.count > 0 }
            
            let roots: [NRPost] = urlEvents
                .map { NRPost(event: $0) }
                .sorted(by: { $0.createdAt > $1.createdAt })
            
            DispatchQueue.main.async {
                onComplete?()
                self.state = .ready(roots)
            }
        }
    }
    
    public func load(url: String) {
        self.state = .loading
        self.fetchKind443sFromRelays(url: url)
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public func error(_ message: String) {
        self.state = .error(message)
    }
    
    public enum State {
        case initializing
        case loading
        case ready([NRPost])
        case timeout
        case error(String)
    }
}
