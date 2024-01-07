//
//  Settings+MainWoTaccountPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2023.
//

import SwiftUI

struct MainWoTaccountPicker: View {
    @EnvironmentObject private var themes:Themes
    @State private var selectedMainWoTaccountPubkey:String // Should just use @AppStorage("app_theme") here, but this freezes on desktop. so workaround via init() and .onChange(of: selectedTheme).
    
    init() {
        let selectedMainWoTaccountPubkey = UserDefaults.standard.string(forKey: "main_wot_account_pubkey") ?? ""
        _selectedMainWoTaccountPubkey = State(initialValue: selectedMainWoTaccountPubkey)
    }
    
    private var accounts:[CloudAccount] { NRState.shared.accounts.filter { $0.publicKey != GUEST_ACCOUNT_PUBKEY } }
    
    static let gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
    
    var body: some View {
        Picker(selection: $selectedMainWoTaccountPubkey) {
            ForEach(accounts) { account in
                HStack {
                    PFP(pubkey: account.publicKey, account: account, size: 20.0)
                    Text(account.anyName)
                }
                .tag(account.publicKey)
                .foregroundColor(themes.theme.primary)
            }
            
        } label: {
            Text("Main account")
        }
        .pickerStyleCompatNavigationLink()
        .onChange(of: selectedMainWoTaccountPubkey) { selectedMainWoTaccountPubkey in
            UserDefaults.standard.set(selectedMainWoTaccountPubkey, forKey: "main_wot_account_pubkey")
        }
    }
}

import NavigationBackport

#Preview {
    PreviewContainer({ pe in pe.loadAccounts() }) {
        NBNavigationStack {
            Form {
                Section(header: Text("Main WoT", comment:"Setting heading on settings screen")) {
                    MainWoTaccountPicker()
                }
            }
        }
    }
}
