//
//  FullAccountPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2025.
//

import SwiftUI

struct FullAccountPicker: View {
    @Binding var selectedAccount: CloudAccount?
    public var label: LocalizedStringKey = LocalizedStringKey("Account")
    public var required: Bool = false
    
    var body: some View {
        AccountPicker(selectedAccount: $selectedAccount, label: label, required: required, fullAccountsOnly: true)
    }
}

struct AccountPicker: View {
    @Binding var selectedAccount: CloudAccount?
    public var label: LocalizedStringKey = LocalizedStringKey("Account")
    public var required: Bool = false
    public var fullAccountsOnly = false
    
    @Environment(\.theme) private var theme
    
    @State private var accounts: [CloudAccount] = []
    
    var body: some View {
        ZStack {
            if !accounts.isEmpty { // .accounts needs to be set or "(CloudAccount) is invalid and does not have an associated tag, this will give undefined results."
                Picker(selection: $selectedAccount) {
                    ForEach(accounts) { account in
                        HStack {
                            PFP(pubkey: account.publicKey, account: account, size: 20.0)
                            Text(account.anyName)
                        }
                        .tag(account)
                        .foregroundColor(theme.primary)
                    }
                    if !required {
                        Text("None")
                            .tag(nil as CloudAccount?)
                    }
                    
                } label: {
                    Text(label)
                }
                .pickerStyleCompatNavigationLink()
            }
        }
        
        .onAppear {
            accounts = (fullAccountsOnly ? AccountsState.shared.fullAccounts : AccountsState.shared.accounts)
                .sorted(by: { $0.publicKey == AccountsState.shared.activeAccountPublicKey && $1.publicKey != AccountsState.shared.activeAccountPublicKey })
        }
        
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var selectedAccount: CloudAccount?
    
    PreviewContainer({ pe in
        pe.loadAccounts()
    }) {
        FullAccountPicker(selectedAccount: $selectedAccount, label: "Authenticate with")
    }
}
