//
//  DeleteAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/03/2023.
//

import SwiftUI
import Combine

struct DeleteAccountSheet: View {
    
    @EnvironmentObject var ns:NosturState
    @Environment(\.dismiss) var dismiss
    @State var remaining = 10
    
    
    let timer = Timer.publish(every: 1, on: .main, in: .common)
    @State var cancel:Cancellable?
    
    
    func count() {
        remaining -= 1
        if remaining <= 0 {
            deleteAccount()
        }
    }
    
    func deleteAccount() {
        guard let account = ns.account else { return }
        AccountManager.shared.wipeAccount(account)
        dismiss()
    }
    
    var body: some View {
        
        VStack {
            if let account = ns.account {
                VStack(alignment: .leading) {
                    Text("Are you sure you want to delete your account?\n", comment: "Confirmation text when you want to delete your account")
                        .font(.headline)
                    
                    HStack {
                        PFP(pubkey: account.publicKey, account: account)
                        VStack(alignment:.leading) {
                            Text("\(ns.account?.display_name ?? "")")
                            Text("@\(ns.account?.name ?? "")")
                        }
                    }
                    
                    Text("\nThis will **wipe** your:\n - Public nostr profile\n - Public nostr following list\n", comment:"Confirmation text when you want to delete your account")
                    
                    Text("This will **delete** your:\n - Account from Nostur\n - Private key (nsec) from Apple Keychain", comment: "Confirmation text when you want to delete your account")
                    
                }
                .padding(30)
                
                if (remaining == 10) {
                    HStack {
                        Button(role: .none) {
                            guard let nsec = account.nsec else { return }
                            UIPasteboard.general.string = nsec
                        } label: {
                            Label(String(localized: "Copy private key", comment: "Button to copy your private key to clipboard"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(role: .destructive) {
                            self.cancel = timer.connect()
                            remaining -= 1
                        } label: {
                            Label("Delete", systemImage: "trash")
                            //                        Image(systemName: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                else {
                    Text("Deleting in \(remaining) seconds", comment: "Text that is counting down when you are deleting your account")
                    Button(role: .cancel) {
                        cancel?.cancel()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            }
        }
        .onReceive(timer, perform: { _ in
            count()
        })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    cancel?.cancel()
                    dismiss()
                }
            }
        }
        .navigationTitle(String(localized:"Delete account", comment: "Navigation title of Delete account screen"))
    }
}

struct DeleteAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NavigationStack {
                DeleteAccountSheet()
            }
        }
    }
}
