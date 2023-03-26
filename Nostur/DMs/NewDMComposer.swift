//
//  NewDMComposer.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI

struct NewDMComposer: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    @Environment(\.dismiss) var dismiss
    @Binding var toPubkey:String?
    @Binding var toContact:Contact?
    @Binding var message:String
    @Binding var showingNewDM:Bool
    @Binding var tab:String
    
    var body: some View {
        VStack {
            // TO (pubkey or contact)
            if let toContact {
                ContactSearchResultRow(contact: toContact)
            }
            else if let toPubkey {
                Text("Sending to: \(try! NIP19(prefix: "npub", hexString: toPubkey).displayString)")
            }
            Spacer()
            // the message
            ChatInputField(message: $message) {
                // Create and send DM (via unpublisher?)
                guard let pk = ns.account?.privateKey else { ns.readOnlyAccountSheetShown = true; return }
                guard let theirPubkey = toPubkey else { return }
                var nEvent = NEvent(content: message)
                nEvent.kind = .directMessage
                if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                    nEvent.content = replaceNsecWithHunter2(nEvent.content)
                }
                guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
                    print("🔴🔴 Could encrypt content")
                    return
                }
                nEvent.content = encrypted
                nEvent.tags.append(NEventTag(type: "p", otherInformation: theirPubkey))
                
                if let signedEvent = try? ns.signEvent(nEvent) {
//                        print(signedEvent.wrappedEventJson())
                    up.publishNow(signedEvent)
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
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    toPubkey = nil
                    toContact = nil
                } label: {
                    Text("Cancel")
                }

            }
        }
    }
}

struct NewDMComposer_Previews: PreviewProvider {
    
    @State static var toPubkey:String? = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
    @State static var toContact:Contact? = nil
    @State static var message = ""
    @State static var showingNewDM = true
    @State static var tab = "Accepted"
    
    static var previews: some View {
        NavigationStack {
            NewDMComposer(toPubkey: $toPubkey, toContact: $toContact, message: $message, showingNewDM: $showingNewDM, tab: $tab)
        }
        .withPreviewEnvironment()
    }
}
