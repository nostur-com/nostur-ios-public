//
//  AccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/02/2023.
//

import SwiftUI
import NavigationBackport

struct AccountsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showSidebar) @Binding private var showSidebar
    
    public var withDismissButton: Bool = true
    public var onDismiss: (() -> Void)?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudAccount.createdAt, ascending: false)],
        animation: .default)
    private var accounts: FetchedResults<CloudAccount>
    private var accountsSorted: [CloudAccount] {
        accounts
            .sorted(by: { $0.lastLoginAt > $1.lastLoginAt })
            .sorted(by: { $0.privateKey != nil && $1.privateKey == nil })
            // always show current logged in account at top
            .sorted(by: { AccountsState.shared.activeAccountPublicKey == $0.publicKey && AccountsState.shared.activeAccountPublicKey != $1.publicKey })
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
                            AccountsState.shared.changeAccount(account)
                            showSidebar = false
                            dismiss()
                            onDismiss?()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(String(localized:"Log out", comment:"Log out button"), role: .destructive) {
                                logoutAccount = account
                            }
                        }
                        .listRowBackground(theme.listBackground)
                }
            }
            .scrollContentBackgroundHidden()
            .listStyle(.plain)
            
            NavigationLink {
                NewAccountSheet()
            } label: { Text("Create new account", comment:"Button to create a new account") }
            
            NavigationLink {
                AddExistingAccountSheet(onDismiss: {
                    dismiss()
                    showSidebar = false
                    onDismiss?()
                })
            } label: { Text("Add existing account", comment:"Button to add an existing account") }
            Spacer()
        }
        .padding(20)
        .navigationTitle(String(localized:"Accounts", comment:"Navigation title for Accounts screen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .cancellationAction) {
                if (withDismissButton) {
                    Button(String(localized: "Close", comment: "Button to close this screen")) {
                        dismiss()
                        showSidebar = false
                        onDismiss?()
                    }
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
                        AccountsState.shared.logout(account)
                    }),
                    .default(Text("Copy private key (nsec) to clipboard", comment: "Button to copy private key to clipboard"), action: {
                        if let pk = account.privateKey {
                            UIPasteboard.general.string = nsec(pk)
                        }
                    }),
                    .cancel(Text("Cancel"))
                ] : [
                    .destructive(Text("Log out", comment: "Button to log out"), action: {
                        AccountsState.shared.logout(account)
                        
//                            if (AccountsState.shared.accounts.isEmpty) { // TODO: inside .logout is async so rewire this?
//                                sendNotification(.hideSideBar)
//                            }
                        
                    }),
                    .cancel(Text("Cancel"))
                ])
        }
        .background(theme.listBackground)
    }
}

struct AccountRow: View {
    @ObservedObject public var account: CloudAccount
    @EnvironmentObject private var accountsState: AccountsState
    
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
            if (account.publicKey == accountsState.activeAccountPublicKey) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundColor(.accentColor)
                    .frame(width: 25, height: 25)
            }
        }
        .padding(5)
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            AccountsSheet()
        }
    }
}
