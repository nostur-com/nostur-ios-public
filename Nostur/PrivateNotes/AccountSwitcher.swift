//
//  AccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/05/2023.
//

import SwiftUI

struct AccountSwitcher: View {
    let accounts:[Account]
    @Binding var selectedAccount:Account?
    
    var body: some View {
        Menu {
            Button {
                $selectedAccount.wrappedValue = nil
            } label: {
                HStack {
                    Text("All accounts", comment: "Menu item to select All accounts")
                    Spacer()
                }
            }
            ForEach(accounts) { account in
                Button {
                    selectedAccount = account
                } label: {
                    HStack {
                        Text(verbatim: "@\(account.name)")
                        Spacer()
                    }
                }
            }
        } label: {
            ZStack {
                if let selectedAccount {
                    PFP(pubkey: selectedAccount.publicKey, account: selectedAccount, size: 30)
                }
                else {
                    ForEach(accounts.indices, id:\.self) { index in
                        PFP(pubkey: accounts[index].publicKey, account: accounts[index], size: 30)
                            .offset(x: -CGFloat(index*10))
                        
                    }
                }
            }
            .padding(.horizontal, 20)
//            .frame(width:100, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
    }
}

struct AccountSwitcher_Previews: PreviewProvider {
    
    @State static var selectedAccount:Account? = nil
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadAccounts()
        }) {
            VStack {
                let accounts = NosturState.shared.accounts
                AccountSwitcher(accounts: accounts, selectedAccount: $selectedAccount)
            }
        }
    }
}
