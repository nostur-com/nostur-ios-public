//
//  PostAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/08/2023.
//

import SwiftUI

struct PostAccountSwitcher: View, Equatable {
    static func == (lhs: PostAccountSwitcher, rhs: PostAccountSwitcher) -> Bool {
        lhs.activeAccount == rhs.activeAccount
    }
    
    public var activeAccount:Account
    public var onChange:(Account) -> ()
    @State private var expanded = false
    
    private var accounts:[Account] {
        NRState.shared.accounts
            .filter { $0.privateKey != nil }
            .sorted(by: {
                $0 == activeAccount && $1 != activeAccount
            })
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Color.clear
            .frame(width: 50, height: 50)
            .overlay(alignment: .topLeading) {
                VStack(spacing: 2) {
                    ForEach(accounts.indices, id:\.self) { index in
                        PFP(pubkey: accounts[index].publicKey, account: accounts[index])
                            .onTapGesture {
                                accountTapped(accounts[index])
                            }
                            .opacity(index == 0 || expanded ? 1.0 : 0.2)
                            .zIndex(-Double(index))
                            .offset(y: expanded || (index == 0) ? 0 : (Double(index) * -48.0))
                            .animation(.easeOut(duration: 0.2), value: expanded)
                    }
                }
                .fixedSize()
            }
    }
    
    private func accountTapped(_ account:Account) {
        if !expanded {
            withAnimation {
                expanded = true
            }
        }
        else {
            withAnimation {
                onChange(account)
                expanded = false
            }
        }
    }
}

struct PostAccountSwitcherPreviewWrap: View {
    @State var activeAccount = NRState.shared.loggedInAccount!.account
    
    var body: some View {
        PostAccountSwitcher(activeAccount: activeAccount, onChange: { account in
            activeAccount = account
        })
    }
}

struct PostAccountSwitcher_Previews: PreviewProvider {

    static var previews: some View {
        PreviewContainer({ pe in pe.loadAccounts() }) {
            PostAccountSwitcherPreviewWrap()
        }
    }
}
