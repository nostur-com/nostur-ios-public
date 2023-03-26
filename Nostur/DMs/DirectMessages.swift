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
    @ObservedObject var nm:NotificationsManager = .shared
    @EnvironmentObject var nav:NavigationModel
    @EnvironmentObject var ns:NosturState
    let pubkey:String
    
//    @FetchRequest
//    var receivedAccepted:FetchedResults<Event>
    
    @FetchRequest
    var received:FetchedResults<Event>
    
    @FetchRequest
    var sent:FetchedResults<Event>
    
    // TODO: Use Algorithms, and .chunked for performance? chain?
    var onlyMostRecentAll:[String: ([Event], Bool, Int, Int64)] { // [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt]
        // The final list of contacts (key) and latest dm (value)
        var recent = [String: ([Event], Bool, Int, Int64)]() // dict: [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt]
        
        // combine all dms, initiated by me and others, and sort them
        let allDms = (Array(sent) + Array(received))
            .sorted(by: { $0.created_at < $1.created_at }) // Root DMs will be index 0
        
        
        for dm in allDms {
            if dm.pubkey == self.pubkey { // dm by me (take event.firstP)
                if let contactPubkey = dm.firstP() {
                    if recent[contactPubkey] == nil {
                        recent[contactPubkey] = ([dm], true, 0, dm.created_at) // sent so consider accepted
                    }
                    else {
                        let dms = recent[contactPubkey]!.0 + [dm]
                        let unread = recent[contactPubkey]!.2 + 0 // +0 because sent by me.
                        recent[contactPubkey] = (dms, true, unread, recent[contactPubkey]!.3) // maybe this dict key was received before, but now also responded so consider accepted
                    }
                }
            }
            else { // dm by someone else (take event.pubkey)
                if recent[dm.pubkey] == nil {
                    let count = dm.created_at > dm.lastSeenDMCreatedAt ? 1 : 0
                    recent[dm.pubkey] = ([dm], dm.dmAccepted, count, dm.created_at) // The first, rootDM, controls isAccepted or not
                                                                 // TODO: check rootDM.lastSeenUnreadDM for +1 or +0
                }
                else {
                    let count = dm.created_at > recent[dm.pubkey]?.0.first?.lastSeenDMCreatedAt ?? 0 ? 1 : 0
                    let dms = recent[dm.pubkey]!.0 + [dm]
                    let unread = recent[dm.pubkey]!.2 + count // TODO: check rootDM.lastSeenUnreadDM for +1 or +0
                    recent[dm.pubkey] = (dms, recent[dm.pubkey]?.1 ?? false, unread, recent[dm.pubkey]!.3)
                }
            }
        }
        
        return recent
    }
    
    var onlyMostRecentAccepted:[(Event, Int)] {
        onlyMostRecentAll
            .filter { $0.value.1 == true }
            .compactMap {
                // Take newest message from the conversation and unread count
                if let newestMessage = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
                    return (
                                newestMessage, // newest message
                                $0.value.2 // unread count
                           )
                }
                else {
                    return nil
                }
            }
            .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
    }
    
    var onlyMostRecentRequests:[(Event, Int64)] {
        onlyMostRecentAll
            .filter { $0.value.1 == false }
            .compactMap {
                if let first = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
                    return (first, $0.value.3)
                }
                return nil
            }
            .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
//            .compactMap {
//                // Take newest message from the conversation and unread count
//                if let newestMessage = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
//                    return (
//                                newestMessage, // newest message
//                                $0.value.2 // unread count
//                           )
//                }
//                else {
//                    return nil
//                }
//            }
//            .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
    }
    
    var onlyMostRecentAcceptedTotalUnread:Int {
        onlyMostRecentAccepted.reduce(0) { (partialResult, recentDMtuple) in
            let (_, unread) = recentDMtuple
            return partialResult + unread
        }
    }
    
    var requestsTotalUnread:Int {
        guard let account = ns.account else { return 0 }
        return onlyMostRecentRequests.reduce(0) { (partialResult, requestDMtuple) in
            let (_, createdAt) = requestDMtuple
            if (createdAt > account.lastSeenDMRequestCreatedAt) {
                return partialResult + 1
            }
            return partialResult
        }
    }
    
//    var onlyMostRecentRequests:[Event] {
//        // The final list of contacts (key) and latest dm (value)
//        var recent = [String: ([Event], Bool)]() // dict: pubkey: (message, isAccepted)
//
//        // combine all dms, initiated by me and others, and sort them
//        let allDms = (Array(sent) + Array(received))
//            .sorted(by: { $0.created_at < $1.created_at })
//
//
//        for dm in allDms {
//            if dm.pubkey == self.pubkey { // dm by me (take event.firstP)
//                if let contactPubkey = dm.firstP() {
//                    if recent[contactPubkey] == nil {
//                        recent[contactPubkey] = ([dm], true) // sent so consider accepted
//                    }
//                    else {
//                        let dms = recent[contactPubkey]!.0 + [dm]
//                        recent[contactPubkey] = (dms, true) // received, but now also responded so consider accepted
//                    }
//                }
//            }
//            else { // dm by someone else (take event.pubkey)
//                if recent[dm.pubkey] == nil {
//                    recent[dm.pubkey] = ([dm], dm.dmAccepted) // The first, rootDM, controls isAccepted or not
//                }
//                else {
//                    let dms = recent[dm.pubkey]!.0 + [dm]
//                    recent[dm.pubkey] = (dms, recent[dm.pubkey]?.1 ?? false)
//                }
//            }
//        }
//
//        return recent
//            .filter { $0.value.1 == false } // only not accepted
//            .compactMap { $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first }
//            .sorted(by: { $0.created_at > $1.created_at }) // not sure if need to sort again?
//    }
    
//    var onlyMostRecentRequests:[Event] {
//        // The final list of contacts (key) and latest dm (value)
//        var recent = [String: Event]()
//
//        // combine all dms, initiated by me and others, and sort them
//        let allRequests = receivedNotAccepted
//            .sorted(by: { $0.created_at > $1.created_at })
//
//
//        for dm in allRequests {
//            if recent[dm.pubkey] == nil {
//                recent[dm.pubkey] = dm
//            }
//        }
//
//        return recent
//            .map { $0.value }
//            .sorted(by: { $0.created_at > $1.created_at }) // not sure if need to sort again?
//    }
    
    @State var selectedRoot:Event?
    @State var showingNewDM = false
    @State var tab = "Accepted"
    
    init(pubkey:String, blockedPubkeys:[String]) {
        self.pubkey = pubkey
        let received = Event.fetchRequest()
        received.predicate = NSPredicate(
            format:
                "kind == 4 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND NOT pubkey IN %@",
            serializedP(pubkey),
            blockedPubkeys)
        received.fetchLimit = 500
        received.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _received = FetchRequest(fetchRequest: received)
        
        let me = Event.fetchRequest()
        me.predicate = NSPredicate(
            format: "kind == 4 AND pubkey == %@", pubkey)
        me.fetchLimit = 500
        me.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _sent = FetchRequest(fetchRequest: me)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $nav.messagesPath) {
            VStack {
                ZStack {
                    VStack {
                        HStack {
                            TabButton(action: {
                                withAnimation {
                                    tab = "Accepted"
                                }
                            }, title: "Accepted", selected: tab == "Accepted", unread: onlyMostRecentAcceptedTotalUnread)
                            
                            TabButton(action: {
                                withAnimation {
                                    if (tab == "Requests") {
                                        updateLastSeenDMRequestCreatedAt()
                                    }
                                    tab = "Requests"
                                }
                            }, title: "Requests", selected: tab == "Requests", unread: requestsTotalUnread)
                        }
//                        Picker(selection: $tab, label: Text("DMs")) {
//                            Text("Accepted").tag("Accepted")
//                            Text("Requests").tag("Requests")
//                        }
//                        .pickerStyle(.segmented)
                        
                        switch (tab) {
                            case "Accepted":
                                if onlyMostRecentAccepted.count > 0 {
                                    List(onlyMostRecentAccepted, id:\.0) { (dm, unread) in
                                        NavigationLink(value: dm) {
                                            DMRow(rootDM: dm, pubkey: pubkey, unread: unread)
                                              
                                        }
                                    }
                                    .listStyle(.plain)
                                }
                                else {
                                    Text("You have not received any messages")
                                        .centered()
                                }
                            case "Requests":
                                if onlyMostRecentRequests.count > 0 {
                                    List(onlyMostRecentRequests, id:\.0) { (dm, rootDMcreatedAt) in
                                        NavigationLink(value: dm) {
                                            DMRow(rootDM: dm, pubkey: pubkey)
                                        }
                                    }
                                    .listStyle(.plain)
                                    .onAppear {
                                        updateLastSeenDMRequestCreatedAt()
                                    }
                                }
                                else {
                                    Text("No message requests")
                                        .centered()
                                }
                            default:
                                EmptyView()
                        }
                        
                    }
                    NewDMButton(showingNewDM: $showingNewDM)
                }
                Text("Note: The contents of DMs is encrypted but the metadata is not. Who you send a messages to and when is public.")
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            }
            .sheet(isPresented: $showingNewDM) {
                NavigationStack {
                    NewDM(showingNewDM: $showingNewDM, tab: $tab)
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
    
    func updateLastSeenDMRequestCreatedAt() {
        guard let account = ns.account else { return }
        guard let latestRootDMcreatedAt = onlyMostRecentRequests.map({ $0.1 }).max() else { return }
        
        account.lastSeenDMRequestCreatedAt = latestRootDMcreatedAt
        // view context save here?? or on close / app background..
    }
}

struct DMRow: View {
    @ObservedObject var rootDM:Event
    let pubkey:String // own account pubkey
    var unread:Int?
    
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
            ZStack {
                PFP(pubkey: contactPubkey, pictureUrl: contact?.picture)
                if let unread {
                    Text("\(unread)")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal,6)
                        .background(Capsule().foregroundColor(.red))
                        .offset(x:15, y: -20)
                        .opacity(unread > 0 ? 1 : 0)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(alignment: .center, spacing:3) {
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
