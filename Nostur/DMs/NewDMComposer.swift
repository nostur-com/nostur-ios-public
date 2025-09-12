//
//  NewDMComposer.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI
import NostrEssentials

struct NewDMComposer: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.dismiss) private var dismiss
    @Binding var toPubkey: String?
    @Binding var toContact: NRContact?
    @Binding var message: String
    @Binding var showingNewDM: Bool
    @Binding var tab: String
    public var preloaded = false
    
    var body: some View {
        VStack {
            // TO (pubkey or contact)
            if let toContact {
                NRContactSearchResultRow(nrContact: toContact)
            }
            else if let toPubkey {
                Text("Sending to: \(try! NIP19(prefix: "npub", hexString: toPubkey).displayString)")
            }
            Spacer()
            // the message
            ChatInputField(message: $message) {
                // Create and send DM (via unpublisher?)
                guard let pk = la.account.privateKey else { AppSheetsModel.shared.readOnlySheetVisible = true; return }
                guard let theirPubkey = toPubkey else { return }
                var nEvent = NEvent(content: message)
                nEvent.kind = .directMessage
                if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                    nEvent.content = replaceNsecWithHunter2(nEvent.content)
                }
                guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
                    L.og.error("🔴🔴 Could encrypt content")
                    return
                }
                nEvent.content = encrypted
                nEvent.tags.append(NostrTag(["p", theirPubkey]))
                
                if let signedEvent = try? la.account.signEvent(nEvent) {
                    //                        print(signedEvent.wrappedEventJson())
                    Unpublisher.shared.publishNow(signedEvent)
                    //                        noteCancellationId = up.publish(signedEvent)
                    message = ""
                    
                    showingNewDM = false
                    tab = "Accepted" // Set tab to accepted so we can see our just sent message
                    dismiss()
                    // spinner
                    // then go to saved event from db after 1 second
                    //                DMConversationView(rootDM: rootDM, pubkey: self.pubkey)
                    
                }
            }
        }
        .padding()
        .navigationTitle(String(localized: "New message", comment: "Navigation title for a new Direct Message"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    if preloaded {
                        showingNewDM = false
                    }
                    else {
                        toPubkey = nil
                        toContact = nil
                    }
                }
            }
        }
    }
}

import NavigationBackport

struct NewDMComposer_Previews: PreviewProvider {
    
    @State static var toPubkey: String? = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
    @State static var toContact: NRContact? = nil
    @State static var message = ""
    @State static var showingNewDM = true
    @State static var tab = "Accepted"
    
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                NewDMComposer(toPubkey: $toPubkey, toContact: $toContact, message: $message, showingNewDM: $showingNewDM, tab: $tab)
            }
        }
    }
}
