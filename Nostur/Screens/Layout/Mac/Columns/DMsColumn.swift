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
    public var config: MacColumnConfig
    
    @StateObject private var vm: DMsVM
    
    @State private var showSettingsSheet = false
    @State private var showNewDMSheet = false

    public init(pubkey: String, navPath: Binding<NBNavigationPath>, columnType: Binding<MacColumnType>, config: MacColumnConfig) {
        self.pubkey = pubkey
        self.config = config
        _navPath = navPath
        _columnType = columnType
        _vm = StateObject(wrappedValue: DMsVM(accountPubkey: pubkey))
    }
    
    var body: some View {
        DMsInnerList(pubkey: pubkey, navPath: $navPath, vm: vm)
            .background(theme.listBackground)
            .sheet(isPresented: $showSettingsSheet) {
                NBNavigationStack {
                    DMSettingsSheet(vm: vm)
                        .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.whenAvailable) // .never is broken on macCatalyst, showSettings = false will not dismiss  .sheet(isPresented: $showSettings) ..
                .presentationBackgroundCompat(theme.listBackground)
            }
            .sheet(isPresented: $showNewDMSheet) {
                NBNavigationStack {
                    SelectDMRecipientSheet(accountPubkey: pubkey, onSelect: { selectedContactPubkey in
                        navPath.append(NewDMConversation(accountPubkey: pubkey, participants: Set([pubkey,selectedContactPubkey])))
                    })
                    .nosturNavBgCompat(theme: theme)
                    .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(theme.listBackground)
            }
            .modifier { // need to hide glass bg in 26+
                if #available(iOS 26.0, *) {
                    $0.toolbar {
                        self.newDMbutton
                            .sharedBackgroundVisibility(.hidden)
                        self.toolbarMenu
                            .sharedBackgroundVisibility(.hidden)
                    }
                }
                else {
                    $0.toolbar {
                        self.newDMbutton
                        self.toolbarMenu
                    }
                }
            }
    }
        
    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if case .DMs(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
                    Button("Change account", systemImage: "person.crop.circle") {
                        columnType = .DMs(nil)
                    }
                }
                Button("Settings", systemImage: "gearshape") {
                    showSettingsSheet = true
                }
            } label: {
                if case .DMs(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
                    PFP(pubkey: accountPubkey, account: account, size: 30)
                    .accessibilityLabel("Account menu")
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var newDMbutton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if !vm.ncNotSupported {
                Button("New Message", systemImage: "square.and.pencil") {
                    guard AccountsState.shared.fullAccounts.contains(where: { $0.publicKey == pubkey }) else {
                        showReadOnlyMessage()
                        return
                    }
                    showNewDMSheet = true
                }
            }
        }
    }
}

struct DMsInnerList: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    
    public let pubkey: String
    @Binding var navPath: NBNavigationPath
    @ObservedObject var vm: DMsVM
    
    @State private var showUpgradeDMsSheet = false
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        if vm.ncNotSupported {
            Text("Direct Messages using a remote signer are not available yet")
                .centered()
        }
        else if vm.ready {
            VStack {
                self.dmAcceptedAndRequesTabs
                
                self.updateNotice
                
                if vm.scanningMonthsAgo != 0 {
                    Text("Scanning relays for messages \(vm.scanningMonthsAgo)/36 months ago...")
                        .italic()
                        .hCentered()
                }
                
                ScrollView {
                    switch (vm.tab) {
                    case "Accepted":
                        if !vm.conversationRows.isEmpty {
                            LazyVStack(alignment: .leading, spacing: GUTTER) {
                                ForEach(vm.conversationRows) { row in
                                    Box(navMode: .noNavigation) {
                                        DMStateRow(dmState: row, accountPubkey: vm.accountPubkey)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // mark as read
                                        navPath.append(row)
                                        row.markedReadAt_ = .now
                                        vm.updateUnreads()
                                    }
                                }
                            }
                        }
                        else {
                            Text("You have not received any messages", comment: "Shown on the DM view when there aren't any direct messages to show")
                                .centered()
                        }
                    case "Requests":
                        if !vm.requestRows.isEmpty || vm.showNotWoT {
                            LazyVStack(alignment: .leading, spacing: GUTTER) {
                                ForEach(vm.requestRows) { row in
                                    Box(navMode: .noNavigation) {
                                        DMStateRow(dmState: row, accountPubkey: vm.accountPubkey)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        navPath.append(row)
                                        row.markedReadAt_ = .now
                                        vm.updateUnreads()
                                    }
                                }
                                
                                if !vm.showNotWoT && !vm.requestRowsNotWoT.isEmpty {
                                    Text("\(vm.requestRowsNotWoT.count) requests not shown")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(5)
                                        .onTapGesture {
                                            vm.showNotWoT = true
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .padding(5)
                        }
                        else {
                            Text("No message requests", comment: "Shown on the DM requests view when there aren't any message requests to show")
                                .centered()
                        }
                    default:
                        EmptyView()
                    }
                    Spacer()
                }
            }
            .background(theme.listBackground)
            .sheet(isPresented: $showUpgradeDMsSheet) {
                NBNavigationStack {
                    UpgradeDMsSheet(accountPubkey: pubkey, onDismiss: {
                        Task { @MainActor [weak vm] in
                            showUpgradeDMsSheet = false
                            vm?.showUpgradeNotice = false
                        }
                    })
                    .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.whenAvailable) // .never is broken on macCatalyst, showSettings = false will not dismiss  .sheet(isPresented: $showSettings) ..
                .presentationBackgroundCompat(theme.listBackground)
            }
    //        .sheet(isPresented: $showSettingsSheet) {
    //            NBNavigationStack {
    //                DMSettingsSheet(vm: vm)
    //                    .environment(\.theme, theme)
    //            }
    //            .nbUseNavigationStack(.whenAvailable) // .never is broken on macCatalyst, showSettings = false will not dismiss  .sheet(isPresented: $showSettings) ..
    //            .presentationBackgroundCompat(theme.listBackground)
    //        }
        }
        else {
            CenteredProgressView()
                .task {
                    await vm.load()
                }
        }
    }
    
    @ViewBuilder
    private var dmAcceptedAndRequesTabs: some View {
        HStack {
            Button {
                withAnimation {
                    vm.tab = "Accepted"
                }
            } label: {
                VStack(spacing: 0) {
                    HStack {
                        Text("Accepted", comment: "Tab title for accepted DMs (Direct Messages)").lineLimit(1)
                            .font(.subheadline)
                            .foregroundColor(theme.accent)
                        if vm.unread > 0 {
                            Menu {
                                Button {
                                    vm.markAcceptedAsRead()
                                } label: {
                                    Label(String(localized: "Mark all as read", comment:"Menu action to mark all messages as read"), systemImage: "envelope.open")
                                }
                            } label: {
                                Text("\(vm.unread)")
                                    .font(.footnote)
                                    .foregroundColor(.white)
                                    .padding(.horizontal,6)
                                    .background(Capsule().foregroundColor(.red))
                                    .offset(x:-4, y: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 41)
                    .fixedSize()
                    theme.accent
                        .frame(height: 3)
                        .opacity(vm.tab == "Accepted" ? 1 : 0.15)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            
            Button {
                withAnimation {
                    vm.tab = "Requests"
                }
            } label: {
                VStack(spacing: 0) {
                    HStack {
                        Text("Requests", comment: "Tab title for DM (Direct Message) requests").lineLimit(1)
                            .font(.subheadline)
                            .foregroundColor(theme.accent)
                        //                                    .frame(maxWidth: .infinity)
                        //                                    .padding(.top, 8)
                        //                                    .padding(.bottom, 5)
                        if vm.newRequests > 0 {
                            Menu {
                                Button {
                                    vm.markRequestsAsRead()
                                } label: {
                                    Label(String(localized: "Mark all as read", comment:"Menu action to mark all dm requests as read"), systemImage: "envelope.open")
                                }
                            } label: {
                                Text("\(vm.newRequests)")
                                    .font(.footnote)
                                    .foregroundColor(.white)
                                    .padding(.horizontal,6)
                                    .background(Capsule().foregroundColor(.red))
                                    .offset(x:-4, y: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 41)
                    .fixedSize()
                    theme.accent
                        .frame(height: 3)
                        .opacity(vm.tab == "Requests" ? 1 : 0.15)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
    }
    
    @ViewBuilder
    private var updateNotice: some View {
        if vm.showUpgradeNotice {
            Button("Upgrade your DMs") {
                showUpgradeDMsSheet = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(theme.accent)  // Matches your app's accent
        }
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
    
//    @State private var showSettingsSheet = false
    
//    @ToolbarContentBuilder
//    private var accountsButton: some ToolbarContent {
//        ToolbarItem(placement: .topBarTrailing) {
//            Menu {
//                if case .DMs(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
//                    Button("Change account", systemImage: "person.crop.circle") {
//                        columnType = .DMs(nil)
//                    }
//                }
//                Button("Settings", systemImage: "gearshape") {
//                    showSettingsSheet = true
//                }
//            } label: {
//                if case .DMs(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
//                    PFP(pubkey: accountPubkey, account: account, size: 30)
//                    .accessibilityLabel("Account menu")
//                }
//            }
//        }
//    }
}

struct DMStateRow: View {
    @ObservedObject private var dmState: CloudDMState
    @State var nrContacts: [NRContact]
    @State var nrContact: NRContact?
    private var unread: Int { dmState.unread(for: accountPubkey) }
    private let accountPubkey: String
    
    init(dmState: CloudDMState, accountPubkey: String) {
        self.dmState = dmState
        self.accountPubkey = accountPubkey
        nrContacts = dmState.receiverPubkeys.map { NRContact.instance(of: $0) }
        if nrContacts.count == 1 {
            nrContact = if let dmStateReceiverPubkey = dmState.receiverPubkeys.first {
                NRContact.instance(of: dmStateReceiverPubkey)
            } else { nil }
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            MultiPFPs(nrContacts: nrContacts)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal,6)
                            .background(Capsule().foregroundColor(.red))
                    }
                }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 5) {
                    if let nrContact {
                        ContactName(nrContact: nrContact)
                            .foregroundColor(.primary)
                            .fontWeightBold()
                            .lineLimit(1)
                        
                        PossibleImposterLabelView(nrContact: nrContact)
                    }
                    else {
                        ForEach(nrContacts) { nrContact in
                            ContactName(nrContact: nrContact)
                                .foregroundColor(.primary)
                                .fontWeightBold()
                                .lineLimit(1)
                        }
                    }
                }

                Text(dmState.blurb)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DMSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: DMsVM
    
    var body: some View {
        NXForm {
            if (vm.unread + vm.newRequests) > 0 {
                Button("Mark all as read") {
                    vm.markAcceptedAsRead()
                    vm.markRequestsAsRead()
                    dismiss()
                }
                .hCentered()
            }
   
            Section {
                HStack {
                    Text("Missing messages?")
                    Button("Rescan") {
                        vm.rescanForMissingDMs(36)
                        dismiss()
                    }
                }
                .hCentered()
            }

            if (vm.newRequestsNotWoT > 0) {
                Section {
                    HStack {
                        Text("\(vm.newRequestsNotWoT) requests outside Web of Trust")
                        if vm.showNotWoT {
                            Button("Hide") {
                                vm.showNotWoT = false
                                dismiss()
                            }
                        }
                        else {
                            Button("Show") {
                                vm.showNotWoT = true
                                vm.tab = "Requests"
                                dismiss()
                            }
                        }
                    }
                    .hCentered()
                }
            }
            
            if (vm.hiddenDMs > 0) {
                Section {
                    HStack {
                        Text("\(vm.hiddenDMs) conversation(s) hidden by you")
                        Button("Unhide") {
                            vm.unhideAll()
                            dismiss()
                        }
                    }
                    .hCentered()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Direct Message Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
    
    @State private var didLoad = false
}
