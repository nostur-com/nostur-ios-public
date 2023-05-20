//
//  AccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/02/2023.
//

import SwiftUI

struct AccountsSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @State var newAccountSheetShown = false
    @State var addExistingAccountSheetShown = false
    
    var withDismissButton:Bool = true
    var sp: SocketPool = .shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)],
        animation: .default)
    private var accounts: FetchedResults<Account>
    
    @State var logoutAccount:Account? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 15) {
                List {
                    ForEach(accounts) { account in
                        AccountRow(account: account)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ns.setAccount(account: account)
                                sendNotification(.hideSideBar)
                                dismiss()
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Log out", role: .destructive) {
                                    logoutAccount = account
                                }
                            }
                    }
                }
                .listStyle(.plain)
                
                NavigationLink {
                    NewAccountSheet()
                } label: { Text("Create new account") }
                
                NavigationLink {
                    AddExistingAccountSheet()
                } label: { Text("Add existing account") }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                if (withDismissButton) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            })
            .actionSheet(item: $logoutAccount) { account in
                ActionSheet(
                    title: Text("Confirm log out"),
                    message: account.privateKey != nil
                    ? Text("""
                                     Make sure you have a back-up of your private key (nsec)
                                     Nostur cannot recover your account without it
                                     """)
                    : Text("""
                                     Account: @\(account.name) / \(account.display_name)
                                     """)
                    ,
                    buttons: account.privateKey != nil
                    ? [
                        .destructive(Text("Log out"), action: {
                            ns.logout(account)
                            
                            if (ns.accounts.count < 1) {
                                sendNotification(.hideSideBar)
                            }
                            
                        }),
                        .default(Text("Copy private key (nsec) to clipboard"), action: {
                            if let pk = ns.account?.privateKey {
                                UIPasteboard.general.string = nsec(pk)
                            }
                        }),
                        .cancel(Text("Cancel"))
                    ] : [
                        .destructive(Text("Log out"), action: {
                            ns.logout(account)
                            
                            if (ns.accounts.count < 1) {
                                sendNotification(.hideSideBar)
                            }
                            
                        }),
                        .cancel(Text("Cancel"))
                    ])
            }
        }
    }
}

struct AccountRow: View {
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            PFP(pubkey: account.publicKey, account: account, size: 35)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        if (account.privateKey == nil) {
                            Text("Read only").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            if (account == ns.account) {
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
        AccountsSheet()
            .withPreviewEnvironment()
    }
}
