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
    
    @StateObject private var vm: DMsVM
    
    public init(pubkey: String, navPath: Binding<NBNavigationPath>, columnType: Binding<MacColumnType>) {
        self.pubkey = pubkey
        _navPath = navPath
        _columnType = columnType
        _vm = StateObject(wrappedValue: DMsVM(accountPubkey: pubkey))
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ScrollView {
            VStack {
                self.dmAcceptedAndRequesTabs
                
                switch (vm.tab) {
                case "Accepted":
                    if !vm.conversationRows.isEmpty {
                        LazyVStack(alignment: .leading) {
                            ForEach(vm.conversationRows) { row in
                                DMStateRow(dmState: row)
                            }
                        }
                    }
                    else {
                        Text("You have not received any messages", comment: "Shown on the DM view when there aren't any direct messages to show")
                            .centered()
                    }
                case "Requests":
                    if !vm.requestRows.isEmpty || vm.showNotWoT {
                        LazyVStack(alignment: .leading) {
                            ForEach(vm.requestRows) { row in
                                Text(row.participantPubkeys.description)
                            }
                        }
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
        .task {
            await vm.load()
        }
        .modifier { // need to hide glass bg in 26+
            if #available(iOS 26.0, *) {
                $0.toolbar {
                    accountsButton
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            else {
                $0.toolbar {
                    accountsButton
                }
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
    
    @ToolbarContentBuilder
    private var accountsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if case .notifications(let accountPubkey) = columnType, let accountPubkey, let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) {
                Button {
                    columnType = .notifications(nil)
                } label: {
                    PFP(pubkey: accountPubkey, account: account, size: 30)
                }
                .accessibilityLabel("Account menu")
            }
        }
    }
}

struct DMStateRow: View {
    @ObservedObject private var dmState: CloudDMState
    @State var nrContacts: [NRContact]
    @State var nrContact: NRContact?
    private var unread: Int { dmState.unread }
    
    init(dmState: CloudDMState) {
        self.dmState = dmState
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
//                                .offset(x:15, y: -20)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 5) {
                    if let nrContact {
                        Group {
                            Text(nrContact.anyName)
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            
                            PossibleImposterLabelView(nrContact: nrContact)
                        }
                    }
                    else {
                        ForEach(nrContacts) { nrContact in
                            Text(nrContact.anyName)
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1)
                        }
                    }
                }

                Text(dmState.blurb).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
