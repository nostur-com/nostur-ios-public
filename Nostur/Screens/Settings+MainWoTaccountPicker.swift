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
        let selectedMainWoTaccountPubkey = UserDefaults.standard.string(forKey: "_mainWoTaccountPubkey") ?? ""
        _selectedMainWoTaccountPubkey = State(initialValue: selectedMainWoTaccountPubkey)
    }
    
    private var accounts:[Account] { NRState.shared.accounts }
    
    static let gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
    
    var body: some View {
        Picker(selection: $selectedMainWoTaccountPubkey) {
            ForEach(accounts) { account in
                HStack {
                    PFP(pubkey: account.publicKey, account: account, size: 20.0)
                    Text(account.anyName)
                }
                .tag(account.publicKey)
            }
            
        } label: {
            Text("Main account")
        }
        .pickerStyle(.navigationLink)
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadAccounts() }) {
        NavigationStack {
            Form {
                Section(header: Text("Main WoT", comment:"Setting heading on settings screen")) {
                    MainWoTaccountPicker()
                }
            }
        }
    }
}
