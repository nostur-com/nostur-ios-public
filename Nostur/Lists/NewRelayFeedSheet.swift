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
    private var rootDismiss: (() -> Void)? = nil
    @State private var wotEnabled = false
    @State private var didLoad = false
    
    private var formIsValid: Bool {
        if relayAddress.isEmpty && relayAddress != "ws://" && relayAddress != "wss://" { return false }
        return true
    }
    
    @State private var relayAddress: String = "wss://"
    
    @State private var accounts: [CloudAccount] = []
    @State private var authenticationAccount: CloudAccount? = nil
    
    var body: some View {
        NXForm {
            Section {
                TextField(text: $relayAddress, prompt: Text("wss://")) {
                    Text("Enter relay address")
                }
                
                Picker(selection: $authenticationAccount) {
                    ForEach(accounts) { account in
                        HStack {
                            PFP(pubkey: account.publicKey, account: account, size: 20.0)
                            Text(account.anyName)
                        }
                        .tag(account)
                        .foregroundColor(theme.primary)
                    }
                    Text("None")
                        .tag(nil as CloudAccount?)
                    
                } label: {
                    Text("Authenticate with")
                }
                .pickerStyleCompatNavigationLink()
                
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
            accounts = AccountsState.shared.accounts.filter { $0.isFullAccount }
                .sorted(by: { $0.publicKey == AccountsState.shared.activeAccountPublicKey && $1.publicKey != AccountsState.shared.activeAccountPublicKey })
            authenticationAccount = accounts.first
        }
        
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
                    newFeed.id = UUID()
                    newFeed.name = relayAddress
                        .replacingOccurrences(of: "ws://", with: "")
                        .replacingOccurrences(of: "wss://", with: "")
                    newFeed.showAsTab = true
                    newFeed.createdAt = .now
                    newFeed.order = 0
                    
                    newFeed.relays = normalizeRelayUrl(relayAddress)
                    newFeed.type = ListType.relays.rawValue
                    
                    // accountPubkey set means auth should be enabled
                    newFeed.accountPubkey = authenticationAccount != nil ? authenticationAccount?.publicKey : nil
                    
                    
                    newFeed.wotEnabled = wotEnabled
                    
                    // Change active tab to this new feed
                    UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
                    UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
                    UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
                    
                    rootDismiss?()
                }
                .disabled(!formIsValid)
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
