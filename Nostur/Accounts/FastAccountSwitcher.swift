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
    
    let MAX_ACCOUNTS = 5
    
    var fewAccounts:ArraySlice<Account> {
        ns.accounts.prefix(MAX_ACCOUNTS)
    }
    
    var body: some View {
        HStack(spacing:10) {
            ForEach(fewAccounts.indices, id:\.self) { index in
                PFP(pubkey: fewAccounts[index].publicKey, pictureUrl: fewAccounts[index].picture, size: 25)
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
