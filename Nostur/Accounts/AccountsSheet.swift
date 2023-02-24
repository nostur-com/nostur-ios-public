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
    @EnvironmentObject var nav:NavigationModel
    @State var newAccountSheetShown = false
    @State var addExistingAccountSheetShown = false
    
    var ep: EventsProvider = .shared
    var sp: SocketPool = .shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)],
        animation: .default)
    private var accounts: FetchedResults<Account>
    
    @State private var confirmDelete = false
    @State var accountToDelete:Account? = nil
    
    var body: some View {
        VStack(spacing: 15) {
            if UIDevice.current.userInterfaceIdiom == .pad {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(30)
                        .onTapGesture {
                            dismiss()
                        }
                }}
            Text("Accounts").font(.title3)
            
            List {
                ForEach(accounts) { account in
                    AccountRow(account: account)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            ns.setAccount(account: account)
                            nav.showSidebar = false
                            dismiss()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                accountToDelete = account
                                confirmDelete.toggle()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            
            HStack {
                Button {
                    newAccountSheetShown = true
                } label: { Text("Create new account") }
                Spacer()
            }
            HStack {
                Button {
                    addExistingAccountSheetShown = true
                } label: { Text("Add existing account") }
                Spacer()
            }
            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $newAccountSheetShown) {
            NewAccountSheet()
        }
        .sheet(isPresented: $addExistingAccountSheetShown) {
            AddExistingAccountSheet()
        }
        .confirmationDialog("Delete account?", isPresented: $confirmDelete) {
            Button(role: .destructive) {
                guard accountToDelete != nil else { return }
                AccountManager.shared.deletePrivateKey(forPublicKeyHex: accountToDelete!.publicKey!)
                if (ns.accounts.count <= 1) {
                    ns.isOnboarding = true
                    nav.showSidebar = false
                    nav.clear()
                    ns.setAccount(account: nil)
                    viewContext.delete(accountToDelete!)
                }
                else {
                    viewContext.delete(accountToDelete!)
                    ns.setAccount(account: ns.accounts.last)
                }
                
                
                dismiss()
                try! viewContext.save()
            } label: {
                Text("Yes, delete account")
            }
        }
    }
}

struct AccountRow: View {
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        if (account.publicKey != nil) {
            HStack(alignment: .center) {
                ProfilePicView(pubkey: account.publicKey!, account: account, size: 35)
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing:3) {
                                Text(account.display_name).font(.headline).foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            
                            HStack {
                                Text("@\(account.name)").font(.subheadline).foregroundColor(.secondary)
                                    .lineLimit(1)
                                if (account.privateKey == nil) {
                                    Text("Read only").font(.system(size: 12.0))
                                        .padding(.horizontal, 8)
                                        .background(.cyan)
                                        .foregroundColor(.white)
//                                        .background(.background)
                                        .cornerRadius(8)
                                        
                                    
                                }
                            }
                        }.multilineTextAlignment(.leading)
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
        }
    }
}

struct AccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        AccountsSheet()
            .withPreviewEnvironment()
    }
}
