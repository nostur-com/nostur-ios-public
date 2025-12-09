//
//  DMsColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2025.
//

import SwiftUI
import NavigationBackport

struct DMsColumn: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    
    public let pubkey: String
    @Binding var navPath: NBNavigationPath
    @Binding var columnType: MacColumnType
    
    @StateObject private var vm: DMsColumnVM
    
    public init(pubkey: String, navPath: Binding<NBNavigationPath>, columnType: Binding<MacColumnType>) {
        self.pubkey = pubkey
        _navPath = navPath
        _columnType = columnType
        _vm = StateObject(wrappedValue: DMsColumnVM(accountPubkey: pubkey))
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZStack {
            theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
            
            LazyVStack {
                ForEach(vm.dmStates) { dmState in
                    Text(dmState.participantPubkeys.description)
                }
                
                // FOLLOWING
                Text("List DMs for \(pubkey) here")
                    .onTapGesture {
                        // Change columnType to DMConversationColumn...
                    }
                    .task {
                        await vm.load()
                    }
            }
        }
        .background(theme.listBackground)
    }
    
//    @ToolbarContentBuilder
//    private func newPostButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .picture(_) = config.columnType { // No settings for .picture
//                Button("Post New Photo", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .picture)
//                }
//            }
//            
//            if case .yak(_) = config.columnType { // No settings for .yak
//                Button("New Voice Message", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .shortVoiceMessage)
//                }
//            }
//        }
//    }
//    
//    @ToolbarContentBuilder
//    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .vine(_) = config.columnType { // No settings for .vine
//               
//            }
//            else { // Settings on every feed type except .vine
//                Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
//                    AppSheetsModel.shared.feedSettingsFeed = config.feed
//                }
//            }
//        }
//    }
}


import Combine

class DMsColumnVM: ObservableObject {
    
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
        conversationRows.reduce(0) { $0 + $1.unread }
    }
    var newRequests: Int {
        requestRows.reduce(0) { $0 + $1.unread }
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
        
    }
    
    @MainActor
    public func markRequestsAsRead() {
        objectWillChange.send()
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
                
                return true
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
