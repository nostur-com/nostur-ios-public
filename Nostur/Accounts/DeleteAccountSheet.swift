//
//  DeleteAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/03/2023.
//

import SwiftUI
import Combine
import NavigationBackport

struct DeleteAccountSheet: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la:LoggedInAccount
    @Environment(\.dismiss) private var dismiss
    @State private var remaining = 10
    
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var cancel:Cancellable?
    
    
    private func count() {
        remaining -= 1
        if remaining <= 0 {
            deleteAccount()
        }
    }
    
    private func deleteAccount() {
        AccountManager.shared.wipeAccount(la.account)
        dismiss()
    }
    
    var body: some View {
        
        VStack {
            VStack(alignment: .leading) {
                Text("Are you sure you want to delete your account?\n", comment: "Confirmation text when you want to delete your account")
                    .font(.headline)
                
                HStack {
                    PFP(pubkey: la.account.publicKey, account: la.account)
                    VStack(alignment:.leading) {
                        Text("\(la.account.display_name)")
                        Text("@\(la.account.name)")
                    }
                }
                
                Text("\nThis will **wipe** your:\n - Public nostr profile\n - Public nostr following list\n", comment:"Confirmation text when you want to delete your account")
                
                Text("This will **delete** your:\n - Account from Nostur\n - Private key (nsec) from Apple Keychain", comment: "Confirmation text when you want to delete your account")
                
            }
            .padding(30)
            
            if (remaining == 10) {
                HStack {
                    Button(role: .none) {
                        guard let nsec = la.account.nsec else { return }
                        UIPasteboard.general.string = nsec
                    } label: {
                        Label(String(localized: "Copy private key", comment: "Button to copy your private key to clipboard"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
                    
                    Button(role: .destructive) {
                        self.cancel = timer.connect()
                        remaining -= 1
                    } label: {
                        Label("Delete", systemImage: "trash")
                        //                        Image(systemName: "trash")
                    }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
                }
            }
            else {
                Text("Deleting in \(remaining) seconds", comment: "Text that is counting down when you are deleting your account")
                Button(role: .cancel) {
                    cancel?.cancel()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(NRButtonStyle(style: .borderedProminent))
            }
        }
        .onReceive(timer, perform: { _ in
            count()
        })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
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
            NBNavigationStack {
                DeleteAccountSheet()
            }
        }
    }
}
