//
//  DirectMessages.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct DirectMessagesContainer: View {
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        if let account = ns.account {
            DirectMessages(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_)
        }
        else {
            Text("No account")
        }
    }
}

struct DirectMessages: View {
    @EnvironmentObject var nav:NavigationModel
    let pubkey:String
    @FetchRequest
    var initiatedByOthers:FetchedResults<Event>
    
    @FetchRequest
    var initiatedByMe:FetchedResults<Event>
    
    var onlyMostRecent:[Event] {
        // The final list of contacts (key) and latest dm (value)
        var recent = [String: Event]()
        
        // combine all dms, initiated by me and others, and sort them
        let allDms = (Array(initiatedByMe) + Array(initiatedByOthers))
            .sorted(by: { $0.created_at > $1.created_at })
        
        
        for dm in allDms {
            if dm.pubkey == self.pubkey { // dm by me (take event.firstP)
                if let contactPubkey = dm.firstP() {
                    if recent[contactPubkey] == nil {
                        recent[contactPubkey] = dm
                    }
                }
            }
            else { // dm by someone else (take event.pubkey)
                if recent[dm.pubkey] == nil {
                    recent[dm.pubkey] = dm
                }
            }
        }
        
        return recent
            .map { $0.value }
            .sorted(by: { $0.created_at > $1.created_at }) // not sure if need to sort again?
    }
    
    @State var selectedRoot:Event?
    @State var showingNewDM = false
    
    init(pubkey:String, blockedPubkeys:[String]) {
        self.pubkey = pubkey
        
        let others = Event.fetchRequest()
        others.predicate = NSPredicate(format: "kind == 4 AND tagsSerialized CONTAINS %@ AND NOT pubkey IN %@", serializedP(pubkey), blockedPubkeys)
        others.fetchLimit = 500
        others.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _initiatedByOthers = FetchRequest(fetchRequest: others)
        
        let me = Event.fetchRequest()
        me.predicate = NSPredicate(
            format: "kind == 4 AND pubkey == %@", pubkey)
        me.fetchLimit = 500
        me.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _initiatedByMe = FetchRequest(fetchRequest: me)
    }
    
    var body: some View {
        NavigationStack(path: $nav.messagesPath) {
            VStack {
                ZStack {
                    if onlyMostRecent.count > 0 {
                        List(onlyMostRecent) { dm in
                            NavigationLink(value: dm) {
                                DMRow(rootDM: dm, pubkey: pubkey)
                            }
                        }
                    }
                    else {
                        Text("You have not received any messages")
                            .centered()
                    }
                    NewDMButton(showingNewDM: $showingNewDM)
                }
                Text("Note: The contents of DMs is encrypted but the metadata is not. Who you send a messages to and when is public.")
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            }
            .sheet(isPresented: $showingNewDM) {
                NavigationStack {
                    NewDM(showingNewDM: $showingNewDM)
                }
            }
            .navigationDestination(for: Event.self) { rootDM in
                DMConversationView(rootDM: rootDM, pubkey: self.pubkey)
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .withNavigationDestinations()
        }
        .task {
            SocketPool.shared
                .sendMessage(
                    ClientMessage(
                        type: .REQ,
                        message: RequestMessage
                            .getAuthorDMs(pubkey: pubkey)))
        }
    }
}

struct DMRow: View {
    @ObservedObject var rootDM:Event
    let pubkey:String // own account pubkey
    
    var contact:Contact? {
        // contact is in .pubkey or in .firstP (depending on incoming/outgoing DM.)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP() {
            return rootDM.contacts?.first(where: { $0.pubkey == firstP })
        }
        else {
            return rootDM.contact
        }
    }
    
    var contactPubkey:String {
        // pubkey is .pubkey or .firstP (depending on incoming/outgoing DM.)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP() {
            return firstP
        }
        else {
            return rootDM.pubkey
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contactPubkey, pictureUrl: contact?.picture)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            if let contact = contact {
                                NameAndNip(contact: contact)
                            }
                            Group {
                                Text("@\(contact?.username ?? String(npub(contactPubkey).prefix(11)))").layoutPriority(1)
                                Text(" · ") //
                                Ago(rootDM.date).layoutPriority(1) //
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(rootDM.noteText).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct DirectMessages_Previews: PreviewProvider {
    static var previews: some View {
        DirectMessages(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", blockedPubkeys: [])
            .withPreviewEnvironment()
    }
}
