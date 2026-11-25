//
//  FastAccountSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/03/2023.
//

import SwiftUI

struct FastAccountSwitcher: View, Equatable {
    
    @EnvironmentObject private var accountsState: AccountsState
    
    static func == (lhs: FastAccountSwitcher, rhs: FastAccountSwitcher) -> Bool {
        lhs.activePubkey == rhs.activePubkey
    }

    public var activePubkey: String = ""
    @Binding public var showSidebar: Bool
    private let MAX_ACCOUNTS = 4
    
    var fewAccounts:ArraySlice<CloudAccount> {
        accountsState.accounts
            .filter { $0.publicKey != activePubkey }
            .sorted(by: { $0.lastLoginAt > $1.lastLoginAt })
            .sorted(by: { $0.isFullAccount && !$1.isFullAccount })
            .prefix(MAX_ACCOUNTS)
    }
    
    var body: some View {
#if DEBUG
//        if #available(iOS 17.1, *) {
//            let _ = Self._logChanges()
//        } else {
//            let _ = Self._printChanges()
//        }
#endif
        HStack(spacing:5) {
            ForEach(fewAccounts, id: \.objectID) { account in
                PFP(pubkey: account.publicKey, account: account, size: 25)
                    .overlay(alignment: .topTrailing) {
                        AccountNotificationBadge(pubkey: account.publicKey)
                    }
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !account.isDeleted, account.managedObjectContext != nil else { return }
                        accountsState.changeAccount(account)
                        showSidebar = false
                    }
            }
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var showSidebar: Bool = false
    
    PreviewContainer({ pe in pe.loadAccounts() }) {
        FastAccountSwitcher(showSidebar: $showSidebar)
    }
}

