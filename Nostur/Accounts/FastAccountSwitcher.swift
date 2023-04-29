//
//  FastAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/03/2023.
//

import SwiftUI

struct FastAccountSwitcher: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sm:SideBarModel
    
    var activePubkey:String = ""
    let MAX_ACCOUNTS = 4
    
    var fewAccounts:ArraySlice<Account> {
        ns.accounts
            .filter { $0.publicKey != activePubkey }
            .prefix(MAX_ACCOUNTS)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        HStack(spacing:5) {
            ForEach(fewAccounts.indices, id:\.self) { index in
                PFP(pubkey: fewAccounts[index].publicKey, pictureUrl: fewAccounts[index].picture, size: 25, isFollowing: true)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ns.setAccount(account: fewAccounts[index])
                        sm.showSidebar = false
                    }
            }
        }
    }
}

struct FastAccountSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        FastAccountSwitcher()
            .withPreviewEnvironment()
    }
}
