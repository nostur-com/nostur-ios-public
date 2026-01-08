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
                    SelectDMRecipientSheet(accountPubkey: pubkey, onSelect: { selectedContactPubkeys in
                        navPath.append(NewDMConversation(accountPubkey: pubkey, participants: selectedContactPubkeys.union([pubkey]), parentDMsVM: vm))
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
