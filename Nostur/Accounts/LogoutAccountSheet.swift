//
//  LogoutAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/09/2025.
//

import SwiftUI

struct LogoutAccountSheet: View {
    @Binding var account: CloudAccount?
    @Binding var showSidebar: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if let account {
            VStack  {
                Text("Account")
                    .fontWeightBold()
                HStack {
                    MiniPFP(pictureUrl: account.pictureUrl)
                    Text(account.anyName)
                }
                
                if showPrivateKeyWarning {
                    Text("Make sure you have a back-up of your private key (nsec). Nostur cannot recover your account without it.", comment: "informational message")
                    .padding()
                    
                    if let nsec = account.nsec {
                        Button(String(localized: "Copy private key (nsec) to clipboard", comment: "Button to copy private key to clipboard")) {
                            UIPasteboard.general.string = nsec
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(Text("Confirm log out", comment: "Sheet title for log out"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                        self.account = nil
                    }
                }
                
                ToolbarItem(placement: .destructiveAction) {
                    Button("Logout", systemImage: "checkmark") {
                        AccountsState.shared.logout(account)
                        showSidebar = false
                        self.account = nil
                    }
                    .buttonStyleGlassProminent(tint: Color.red)
                    .help("Logout")
                }
            }
        }
    }
    
    private var showPrivateKeyWarning: Bool {
        if let account {
            return !account.isNC && account.privateKey != nil
        }
        return false
    }
}

import NavigationBackport

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var logoutAccount: CloudAccount?
    @Previewable @State var showSidebar: Bool = true
    PreviewContainer {
        if let account = AccountsState.shared.loggedInAccount?.account {
            NBNavigationStack {
                LogoutAccountSheet(account: $logoutAccount, showSidebar: $showSidebar)
            }
            .onAppear {
                logoutAccount = account
            }
        }
    }
}
