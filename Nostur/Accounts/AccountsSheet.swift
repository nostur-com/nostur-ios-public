//
//  AccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/02/2023.
//

import SwiftUI
import NavigationBackport

struct AccountsSheet: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    @State private var newAccountSheetShown = false
    @State private var addExistingAccountSheetShown = false
    
    public var withDismissButton: Bool = true
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudAccount.createdAt, ascending: false)],
        animation: .default)
    private var accounts: FetchedResults<CloudAccount>
    private var accountsSorted: [CloudAccount] {
        accounts
            .sorted(by: { $0.lastLoginAt > $1.lastLoginAt })
            .sorted(by: { $0.privateKey != nil && $1.privateKey == nil })
            // always show current logged in account at top
            .sorted(by: { NRState.shared.activeAccountPublicKey == $0.publicKey && NRState.shared.activeAccountPublicKey != $1.publicKey })
    }
    
    @State private var logoutAccount: CloudAccount? = nil
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing: 15) {
            List {
                ForEach(accountsSorted) { account in
                    AccountRow(account: account)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NRState.shared.changeAccount(account)
                            sendNotification(.hideSideBar)
                            dismiss()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(String(localized:"Log out", comment:"Log out button"), role: .destructive) {
                                logoutAccount = account
                            }
                        }
                }
                .listRowBackground(themes.theme.background)
            }
            .scrollContentBackgroundHidden()
            .listStyle(.plain)
            
            NavigationLink {
                NewAccountSheet()
            } label: { Text("Create new account", comment:"Button to create a new account") }
            
            NavigationLink {
                AddExistingAccountSheet()
            } label: { Text("Add existing account", comment:"Button to add an existing account") }
            Spacer()
        }
        .padding(20)
        .navigationTitle(String(localized:"Accounts", comment:"Navigation title for Accounts screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .cancellationAction) {
                if (withDismissButton) {
                    Button(String(localized: "Close", comment: "Button to close this screen")) { dismiss() }
                }
            }
        })
        .actionSheet(item: $logoutAccount) { account in
            ActionSheet(
                title: Text("Confirm log out", comment: "Title of sheet that asks the user to confirm logout action"),
                message: !account.isNC && account.privateKey != nil
                ? Text("""
                                 Make sure you have a back-up of your private key (nsec)
                                 Nostur cannot recover your account without it
                                 """, comment: "Informational text during logout action")
                : Text("""
                                 Account: @\(account.name) / \(account.display_name)
                                 """, comment: "Informational text during logout action, showing Account name/handle")
                ,
                buttons: !account.isNC && account.privateKey != nil
                ? [
                    .destructive(Text("Log out", comment: "Button to log out"), action: {
                        NRState.shared.logout(account)
                        
//                            if (NRState.shared.accounts.isEmpty) { // TODO: inside .logout is async so rewire this?
//                                sendNotification(.hideSideBar)
//                            }
                        
                    }),
                    .default(Text("Copy private key (nsec) to clipboard", comment: "Button to copy private key to clipboard"), action: {
                        if let pk = account.privateKey {
                            UIPasteboard.general.string = nsec(pk)
                        }
                    }),
                    .cancel(Text("Cancel"))
                ] : [
                    .destructive(Text("Log out", comment: "Button to log out"), action: {
                        NRState.shared.logout(account)
                        
//                            if (NRState.shared.accounts.isEmpty) { // TODO: inside .logout is async so rewire this?
//                                sendNotification(.hideSideBar)
//                            }
                        
                    }),
                    .cancel(Text("Cancel"))
                ])
        }
        .background(themes.theme.background)
    }
}

struct AccountRow: View {
    @ObservedObject public var account: CloudAccount
    @EnvironmentObject private var ns: NRState
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            PFP(pubkey: account.publicKey, account: account, size: DIMENSIONS.POST_ROW_PFP_DIAMETER)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.anyName).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        if (account.privateKey == nil) {
                            Text("Read only", comment: "Label to indicate this a Read Only account").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        if (account.isNC) {
                            Text(verbatim: "nsecBunker").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.indigo)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            if (account.publicKey == ns.activeAccountPublicKey) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundColor(.accentColor)
                    .frame(width: 25, height: 25)
            }
        }
        .padding(5)
    }
}

struct AccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                AccountsSheet()
            }
        }
    }
}
