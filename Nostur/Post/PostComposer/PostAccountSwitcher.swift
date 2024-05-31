//
//  PostAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/08/2023.
//

import SwiftUI

struct InlineAccountSwitcher: View, Equatable {
    static func == (lhs: InlineAccountSwitcher, rhs: InlineAccountSwitcher) -> Bool {
        lhs.activeAccount == rhs.activeAccount //&& lhs.accounts.count == rhs.accounts.count
    }
    
    public var activeAccount: CloudAccount
    public var onChange: (CloudAccount) -> ()
    public var size: CGFloat = 50.0
    
    @State private var expanded = false
    
    @State private var accounts: [CloudAccount] = []
    
    private var accountsSorted: [CloudAccount] {
        accounts
            .sorted(by: {
                $0.lastLoginAt > $1.lastLoginAt
            })
            .sorted(by: {
                $0 == activeAccount && $1 != activeAccount
            })
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Color.clear
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                VStack(spacing: 2) {
                    ForEach(accountsSorted.indices, id:\.self) { index in
                        PFP(pubkey: accountsSorted[index].publicKey, account: accountsSorted[index], size: size)
                            .onTapGesture {
                                accountTapped(accountsSorted[index])
                            }
                            .opacity(index == 0 || expanded ? 1.0 : 0.2)
                            .zIndex(-Double(index))
                            .offset(y: expanded || (index == 0) ? 0 : (Double(index) * -(size - 2)))
                            .animation(.easeOut(duration: 0.2), value: expanded)
                            .id(accountsSorted[index].publicKey) // sorting index and view identity (publicKey) is different!
                    }
                }
                .fixedSize()
            }
            .task {
                accounts = NRState.shared.accounts
                    .filter { $0.isFullAccount }
//                    .sorted(by: {
//                        $0 == activeAccount && $1 != activeAccount
//                    })
            }
    }
    
    private func accountTapped(_ account:CloudAccount) {
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

struct InlineAccountSwitcherPreviewWrap: View {
    @State var activeAccount = NRState.shared.loggedInAccount!.account
    
    var body: some View {
        InlineAccountSwitcher(activeAccount: activeAccount, onChange: { account in
            activeAccount = account
        }, size: 20.0)
    }
}

struct InlineAccountSwitcher_Previews: PreviewProvider {

    static var previews: some View {
        PreviewContainer({ pe in pe.loadAccounts() }) {
            InlineAccountSwitcherPreviewWrap()
        }
    }
}
