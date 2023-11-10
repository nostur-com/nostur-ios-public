//
//  FastAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/03/2023.
//

import SwiftUI

struct FastAccountSwitcher: View, Equatable {

    static func == (lhs: FastAccountSwitcher, rhs: FastAccountSwitcher) -> Bool {
        lhs.activePubkey == rhs.activePubkey
    }
    
    @EnvironmentObject private var ns:NRState
    
    public var activePubkey:String = ""
    public var sm:SideBarModel
    private let MAX_ACCOUNTS = 4
    
    var fewAccounts:ArraySlice<CloudAccount> {
        ns.accounts
            .filter { $0.publicKey != activePubkey }
            .sorted(by: { $0.lastLoginAt > $1.lastLoginAt })
            .sorted(by: { $0.privateKey != nil && $1.privateKey == nil })
            .prefix(MAX_ACCOUNTS)
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack(spacing:5) {
            ForEach(fewAccounts.indices, id:\.self) { index in
                PFP(pubkey: fewAccounts[index].publicKey, account: fewAccounts[index], size: 25)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let account = fewAccounts[safe: index] { // Swift runtime failure: Index out of bounds + 0 (<compiler-generated>:0) . Added check because maybe tap gesture fires too late??
                            ns.changeAccount(account)
                            sm.showSidebar = false
                        }
                    }
            }
        }
    }
}

struct FastAccountSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadAccounts() }) {
            FastAccountSwitcher(sm: PreviewEnvironment.shared.sm)
        }
    }
}
