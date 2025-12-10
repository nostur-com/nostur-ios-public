//
//  DMsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/12/2025.
//

import SwiftUI
import Combine

class DMsVM: ObservableObject {
    
    @Published var tab = "Accepted"
    public var dmStates: [CloudDMState] = []
//    {
//        didSet {
//            allowedWoT = Set(dmStates.filter { $0.accepted }.compactMap { $0.contactPubkey_ })
//        }
//    }
    
    // pubkeys we started a conv with (but maybe not in WoT), should be allowed in DM WoT
    // Add this to WoT
//    public var allowedWoT: Set<String> = []
    
    var accountPubkey: String
    var didLoad = false
    
    @Published var conversationRows: [CloudDMState] = []
    @Published var requestRows: [CloudDMState] = []
    @Published var requestRowsNotWoT: [CloudDMState] = []
    
    @Published var showNotWoT = false {
        didSet {
            if showNotWoT {
                requestRows = requestRows + requestRowsNotWoT
            }
            else {
                self.reloadConversations()
            }
        }
    }
     
    var unread: Int {
        conversationRows.reduce(0) { $0 + $1.unread(for: self.accountPubkey) }
    }
    var newRequests: Int {
        requestRows.reduce(0) { $0 + $1.unread(for: self.accountPubkey) }
    }
    
    var newRequestsNotWoT: Int {
        requestRowsNotWoT.count
    }
    
    public var hiddenDMs: Int {
        dmStates.count { $0.isHidden }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    init(accountPubkey: String) {
        self.accountPubkey = accountPubkey
        self._reloadConversations
            .debounce(for: 1.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadConversations()
                }
            }
            .store(in: &self.subscriptions)
        
        receiveNotification(.blockListUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.showNotWoT = false
                    self?.loadConversations()
                }
            }
            .store(in: &self.subscriptions)
    }
    // .load is called from:
    // NRState on startup if WoT is disabled
    // receiveNotification(.WoTReady) if WoT is enabled, after WoT has loaded
    @MainActor
    public func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        conversationRows = []
        requestRows = []
        requestRowsNotWoT = []
        
        self.loadDMStates()
        self.loadConversations()
        didLoad = true
    }
    
    @MainActor
    private func loadDMStates() {
        self.dmStates = CloudDMState.fetchByAccount(self.accountPubkey, context: viewContext())
    }
    
    @MainActor
    public func reload(accountPubkey: String) async {
        self.accountPubkey = accountPubkey
        await self.load(force: true)
    }
    
    @MainActor
    public func markAcceptedAsRead() {
        objectWillChange.send()
        for dmState in conversationRows {
            dmState.markedReadAt_ = Date.now
            dmState.didUpdate.send()
        }
    }
    
    @MainActor
    public func markRequestsAsRead() {
        objectWillChange.send()
        for dmState in requestRows {
            dmState.markedReadAt_ = Date.now
            dmState.didUpdate.send()
        }
        if showNotWoT {
            for dmState in requestRowsNotWoT {
                dmState.markedReadAt_ = Date.now
                dmState.didUpdate.send()
            }
        }
    }
    
    
    public func reloadConversations() { _reloadConversations.send() }
    private var _reloadConversations = PassthroughSubject<Void, Never>()
    
    @MainActor
    private func loadConversations() {
        let blockedPubkeys = blocks()
        
        let accepted = dmStates
            .filter { dmState in
                
                if !dmState.accepted && !dmState.isHidden { return false } // only accepted and not hidden
                
                // not blocked (for 1 on 1). In group conversations need to block in the detail view
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first, blockedPubkeys.contains(contactPubkey) {
                    return false
                }
                
                return true
            }
        
        let requests = dmStates
            .filter { dmState in
                if dmState.accepted || dmState.isHidden { return false } // only requests (not accepted), or not hidden
                
                
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first {
                    
                    // not blocked (for 1 on 1). In group conversations need to block in the detail view
                    if blockedPubkeys.contains(contactPubkey) {
                        return false
                    }
                   
                    // only in WoT (if WoT is enabled)
                    if (!WOT_FILTER_ENABLED()) { return true }
                    return WebOfTrust.shared.isAllowed(contactPubkey)
                }
                
                return true
            }
        
        conversationRows = accepted
        requestRows = requests
        
        guard WOT_FILTER_ENABLED() else { return }
        
        let outsideWoT = dmStates
            .filter { dmState in
                if dmState.accepted || dmState.isHidden { return false } // only requests (not accepted), or not hidden
                
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first {
                    // not blocked
                    if blockedPubkeys.contains(contactPubkey) {
                        return false
                    }
                   
                    // only not in WoT
                    return !WebOfTrust.shared.isAllowed(contactPubkey)
                }
                
                return false
            }

        requestRowsNotWoT = outsideWoT
    }
    
    public func unhideAll() {
        for dmState in dmStates {
            if dmState.isHidden {
                dmState.isHidden = false
            }
        }
    }
    
    public func newMessage() {
        Task { @MainActor in
            self.loadDMStates()
        }
    }
}
