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
        VStack(spacing: 15) {
            NXList(plain: true, showListRowSeparator: true) {
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
                    Button(String(localized: "Close", comment: "Button to close this screen"), systemImage: "xmark") {
                        dismiss()
                        showSidebar = false
                        onDismiss?()
                    }
                }
            }
        })
        .sheet(item: $logoutAccount, content: { account in
            NBNavigationStack {
                LogoutAccountSheet(account: $logoutAccount, showSidebar: .constant(false))
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
            .presentationDetents350l()
        })
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
                            Text(verbatim: "remote signer").font(.system(size: 12.0))
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
