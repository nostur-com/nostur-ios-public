//
//  NewRelayFeedSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2025.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct NewRelayFeedSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    public var rootDismiss: (() -> Void)? = nil
    @State private var wotEnabled = false
    @State private var didLoad = false
    
    private var formIsValid: Bool {
        if relayAddress.isEmpty && relayAddress != "ws://" && relayAddress != "wss://" { return false }
        return true
    }
    
    @State private var relayAddress: String = "wss://"
    
    @State private var accounts: [CloudAccount] = []
    @State private var authenticationAccount: CloudAccount? = nil
    
    @FocusState private var relayAddressIsFocused: Bool
    
    var body: some View {
        NXForm {
            Section {
                TextField(text: $relayAddress, prompt: Text("wss://")) {
                    Text("Enter relay address")
                }
                .focused($relayAddressIsFocused)
                
                FullAccountPicker(selectedAccount: $authenticationAccount, label: "Authenticate as")
                
            } header: {
                Text("Enter relay address")
            } footer: {
                if authenticationAccount == nil {
                    Text("Some relays may require authentication")
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                }
            }
            
            Section(header: Text("Web of Trust spam filter", comment: "Header for a feed setting")) {
                Toggle(isOn: $wotEnabled) {
                    Text("Only show content from your follows or follows-follows")
                }
            }
        }

        
        .navigationTitle(String(localized:"New feed", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)
        
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            relayAddressIsFocused = true
            authenticationAccount = AccountsState.shared.fullAccounts
                .sorted(by: { $0.publicKey == AccountsState.shared.activeAccountPublicKey && $1.publicKey != AccountsState.shared.activeAccountPublicKey })
                .first
        }
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
                    newFeed.id = UUID()
                    newFeed.name = relayAddress
                        .replacingOccurrences(of: "ws://", with: "")
                        .replacingOccurrences(of: "wss://", with: "")
                    newFeed.showAsTab = true
                    newFeed.createdAt = .now
                    newFeed.order = 0
                    
                    newFeed.relays = normalizeRelayUrl(relayAddress)
                    newFeed.type = CloudFeedType.relays.rawValue
                    
                    // Resume Where Left: Default on for contact-based. Default off for relay-based
                    newFeed.continue = false
                    
                    // accountPubkey set means auth should be enabled
                    if let authenticationAccount {
                        let accountPubkey = authenticationAccount.publicKey
                        newFeed.accountPubkey = accountPubkey
                        
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            ConnectionPool.shared.relayFeedAuthPubkeyMap[normalizeRelayUrl(relayAddress)] = accountPubkey
                        }
                    }
                    
                    
                    newFeed.wotEnabled = wotEnabled
                    
                    if IS_DESKTOP_COLUMNS() {
                        // Create new column, or replace last column (if too many)
                        withAnimation {
                            if !MacColumnsVM.shared.allowAddColumn {
                                MacColumnsVM.shared.columns.removeLast()
                            }
                            MacColumnsVM.shared.addColumn(MacColumnConfig(type: .cloudFeed(newFeed.id?.uuidString ?? "?")))
                        }
                    }
                    else {
                        // Change active tab to this new feed
                        UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
                        UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
                        UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
                    }
                    
                    rootDismiss?()
                }
                .buttonStyleGlassProminent()
                .disabled(!formIsValid)
            }
        }
    }
}

// Almost copy pastge of NewRelayFeedSheet, but needed a bit different as quick configuration step for auth before relay preview
struct RelayPreviewFeedSheet: View {
    @EnvironmentObject private var loggedInAccount: LoggedInAccount
    @Environment(\.theme) private var theme
    public var prefillAddress: String
    @State private var wotEnabled = false
    @State private var didLoad = false
    
    private var formIsValid: Bool {
        if relayAddress.isEmpty && relayAddress != "ws://" && relayAddress != "wss://" { return false }
        return true
    }
    
    @State private var relayAddress: String = "wss://"
    
    @State private var authenticationAccount: CloudAccount? = nil
    
    @State private var showRelayPreview = false
    @State private var relayPreviewConfig: NXColumnConfig? = nil
    
    var body: some View {
        NXForm {
            Section {
                TextField(text: $relayAddress, prompt: Text("wss://")) {
                    Text("Enter relay address")
                }
                
                FullAccountPicker(selectedAccount: $authenticationAccount, label: "Authenticate as")
                
            } header: {
                Text("Connection")
            } footer: {
                if authenticationAccount == nil {
                    Text("Some relays may require authentication")
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                }
            }
            
            Section {
                Toggle(isOn: $wotEnabled) {
                    Text("Web of Trust spam filter")
                    Text("Only show content from your follows or follows-follows")
                }
            }
        }
        
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            relayAddress = prefillAddress
            // Preselect default auth account
            authenticationAccount = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == AccountsState.shared.activeAccountPublicKey })
        }
        
        .navigationTitle(String(localized: "Configure", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    AppSheetsModel.shared.dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Show preview") {
                   showPreview()
                }
                .disabled(!formIsValid)
            }
        }
        
        .nbNavigationDestination(isPresented: $showRelayPreview) {
            ZStack(alignment: .center) {
                if !IS_IPHONE {
                    Color.black.opacity(0.5)
                }
                AvailableWidthContainer {
                    if let relayPreviewConfig {
                        RelayFeedPreviewSheet(config: relayPreviewConfig, authPubkey: authenticationAccount?.publicKey)
                            .environment(\.theme, theme)
                            .environmentObject(loggedInAccount)
                    }
                    else {
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: !IS_IPHONE ? 560 : .infinity) // Don't make very wide feed on Desktop
        }
    }
    
    func showPreview() {
        let relayData = RelayData.new(url: normalizeRelayUrl(relayAddress))
        let config = NXColumnConfig(id: "RelayFeedPreview", columnType: .relayPreview(relayData), name: "Relay Preview")
        
        if let authenticationAccount { // Enable auth for relay preview
            let accountPubkey = authenticationAccount.publicKey
            ConnectionPool.shared.queue.async(flags: .barrier) {
                ConnectionPool.shared.relayFeedAuthPubkeyMap[normalizeRelayUrl(relayAddress)] = accountPubkey
            }
        }
        
        // Temporarily add relay connection to connection pool, or REQ will go nowhere
        ConnectionPool.shared.addConnection(relayData) { conn in
            conn.connect()
            
            Task { @MainActor in
                relayPreviewConfig = config
                showRelayPreview = true
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadContacts()
        pe.loadCloudFeeds()
        pe.loadRelays()
    }) {
        NBNavigationStack {
            NewRelayFeedSheet()
        }
    }
}
