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

func computeOnlyMostRecentAll(sent:[Event],received:[Event],pubkey:String) -> [String: ([Event], Bool, Int, Int64, Event)] {
    var recent = [String: ([Event], Bool, Int, Int64, Event)]() // dict: [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt, rootDM]
    
    // combine all dms, initiated by me and others, and sort them
    let allDms = (sent + received)
        .sorted(by: { $0.created_at < $1.created_at }) // Root DMs will be index 0
    
    
    for dm in allDms {
        if dm.pubkey == pubkey { // dm by me (take event.firstP)
            if let contactPubkey = dm.firstP() {
                if recent[contactPubkey] == nil {
                    recent[contactPubkey] = ([dm], true, 0, dm.created_at, dm) // sent so consider accepted
                }
                else {
                    let dms = recent[contactPubkey]!.0 + [dm]
                    let unread = recent[contactPubkey]!.2 + 0 // +0 because sent by me.
                    recent[contactPubkey] = (dms, true, unread, recent[contactPubkey]!.3, recent[contactPubkey]!.4) // maybe this dict key was received before, but now also responded so consider accepted
                }
            }
        }
        else { // dm by someone else (take event.pubkey)
            if recent[dm.pubkey] == nil {
                let count = dm.created_at > dm.lastSeenDMCreatedAt ? 1 : 0
                recent[dm.pubkey] = ([dm], dm.dmAccepted, count, dm.created_at, dm) // The first, rootDM, controls isAccepted or not
                                                             // check rootDM.lastSeenDMCreatedAt for +1 or +0
            }
            else {
                let current = recent[dm.pubkey]
                let count = dm.created_at > current?.0.first?.lastSeenDMCreatedAt ?? 0 ? 1 : 0
                let dms = current!.0 + [dm]
                let unread = current!.2 + count // check rootDM.lastSeenDMCreatedAt for +1 or +0
                let isAccepted = current!.1 || (current?.0.first?.dmAccepted ?? false)
                recent[dm.pubkey] = (dms, isAccepted, unread, recent[dm.pubkey]!.3, recent[dm.pubkey]!.4)
            }
        }
    }
    
    return recent
}

func computeOnlyMostRecentAccepted(_ onlyMostRecentAll:[String: ([Event], Bool, Int, Int64, Event)]) -> [(Event, Int)] {
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

func computeOnlyMostRecentRequests(_ onlyMostRecentAll:[String: ([Event], Bool, Int, Int64, Event)]) -> [(Event, Int64)] {
    onlyMostRecentAll
        .filter { $0.value.1 == false }
        .compactMap {
            if let first = $0.value.0.sorted(by: { $0.created_at > $1.created_at }).first {
                return (first, $0.value.3)
            }
            return nil
        }
        .sorted(by: { $0.0.created_at > $1.0.created_at }) // not sure if need to sort again?
}

func computeOnlyMostRecentAcceptedTotalUnread(_ onlyMostRecentAccepted:[(Event, Int)]) -> Int {
    onlyMostRecentAccepted.reduce(0) { (partialResult, recentDMtuple) in
        let (_, unread) = recentDMtuple
        return partialResult + unread
    }
}

func computeRequestTotalUnread(_ onlyMostRecentRequests:[(Event, Int64)], lastSeenDMRequestCreatedAt:Int64) -> Int {
    return onlyMostRecentRequests.reduce(0) { (partialResult, requestDMtuple) in
        let (_, createdAt) = requestDMtuple
        if (createdAt > lastSeenDMRequestCreatedAt) {
            return partialResult + 1
        }
        return partialResult
    }
}

struct DirectMessages: View {
    @ObservedObject var nm:NotificationsManager = .shared
    @State var navPath = NavigationPath()
    @AppStorage("selected_tab") var selectedTab = "Messages"
    @EnvironmentObject var ns:NosturState
    let pubkey:String
    
    @FetchRequest
    var received:FetchedResults<Event>
    
    @FetchRequest
    var sent:FetchedResults<Event>
    
    var onlyMostRecentAll:[String: ([Event], Bool, Int, Int64, Event)] { // [pubkey: [dm], isAccepted, unreadCount, rootDM.createdAt, rootDM]
        // The final list of contacts (key) and latest dm (value)
        return computeOnlyMostRecentAll(sent: Array(sent), received: Array(received), pubkey: pubkey)
    }
    
    var onlyMostRecentAccepted:[(Event, Int)] {
        return computeOnlyMostRecentAccepted(onlyMostRecentAll)
    }
    
    var onlyMostRecentRequests:[(Event, Int64)] {
        return computeOnlyMostRecentRequests(onlyMostRecentAll)
    }
    
    var onlyMostRecentAcceptedTotalUnread:Int {
        return computeOnlyMostRecentAcceptedTotalUnread(onlyMostRecentAccepted)
    }
    
    var requestsTotalUnread:Int {
        guard let account = ns.account else { return 0 }
        return computeRequestTotalUnread(onlyMostRecentRequests, lastSeenDMRequestCreatedAt: account.lastSeenDMRequestCreatedAt)
    }
    
    var onlyMostRecentAcceptedFiltered:[(Event, Int)] {
        if debounceObject.debouncedText != "" {
            return onlyMostRecentAccepted.filter { (dm, _) in
                return (dm.contact?.name?.contains(debounceObject.debouncedText) ?? false) ||
                (dm.contact?.display_name?.contains(debounceObject.debouncedText) ?? false)
            }
        }
        return onlyMostRecentAccepted
    }
    
    @State var selectedRoot:Event?
    @State var showingNewDM = false
    @State var tab = "Accepted"
    @StateObject var debounceObject = DebounceObject()
    
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
        received.fetchLimit = 999
        received.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _received = FetchRequest(fetchRequest: received)
        
        let sent = Event.fetchRequest()
        sent.predicate = NSPredicate(
            format: "kind == 4 AND pubkey == %@", pubkey)
        sent.fetchLimit = 999
        sent.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _sent = FetchRequest(fetchRequest: sent)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                ZStack {
                    VStack {
                        HStack {
                            Button {
                                withAnimation {
                                    tab = "Accepted"
                                }
                            } label: {
                                VStack(spacing:0) {
                                    HStack {
                                        Text("Accepted").lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .padding(.top, 8)
                                            .padding(.bottom, 5)
                                        if onlyMostRecentAcceptedTotalUnread > 0 {
                                            Menu {
                                                Button { markAllAsRead() } label: {
                                                    Label("Mark all as read", systemImage: "envelope.open")
                                                }
                                            } label: {
                                                Text("\(onlyMostRecentAcceptedTotalUnread)")
                                                    .font(.footnote)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal,6)
                                                    .background(Capsule().foregroundColor(.red))
                                                    .offset(x:-4, y: 0)
                                            }
                                        }
                                    }
                                    Rectangle()
                                        .frame(height: 3)
                                        .background(Color("AccentColor"))
                                        .opacity(tab == "Accepted" ? 1 : 0.15)
                                }
                            }
                            .contentShape(Rectangle())
                            
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
                                    List(onlyMostRecentAcceptedFiltered, id:\.0) { (dm, unread) in
                                        NavigationLink(value: dm) {
                                            DMRow(recentDM: dm, pubkey: pubkey, unread: unread)
                                        }
                                    }
                                    .listStyle(.plain)
                                    .onAppear {
                                        sendNotification(.updateDMsCount, requestsTotalUnread + onlyMostRecentAcceptedTotalUnread)
                                    }
//                                    .searchable(text: $debounceObject.text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Filter by name"))
                                }
                                else {
                                    Text("You have not received any messages")
                                        .centered()
                                }
                            case "Requests":
                                if onlyMostRecentRequests.count > 0 {
                                    List(onlyMostRecentRequests, id:\.0) { (dm, rootDMcreatedAt) in
                                        NavigationLink(value: dm) {
                                            DMRow(recentDM: dm, pubkey: pubkey)
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
                DMConversationView(recentDM: rootDM, pubkey: self.pubkey)
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
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD else { return }
            guard selectedTab == "Messages" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            navPath.removeLast(navPath.count)
        }
    }
    
    func markAllAsRead() {
        onlyMostRecentAll.filter { $0.value.1 == true && $0.value.2 > 0 }
            .forEach { (key: String, value: ([Event], Bool, Int, Int64, Event)) in
                if let last = value.0.last {
                    let rootDM = value.4
                    rootDM.objectWillChange.send()
                    rootDM.lastSeenDMCreatedAt = last.created_at
                }
            }
        DataProvider.shared().save()
        sendNotification(.updateDMsCount, requestsTotalUnread + 0)
    }
    
    func updateLastSeenDMRequestCreatedAt() {
        guard let account = ns.account else { return }
        guard let latestRootDMcreatedAt = onlyMostRecentRequests.map({ $0.1 }).max() else { return }
        
        account.lastSeenDMRequestCreatedAt = latestRootDMcreatedAt
        sendNotification(.updateDMsCount, requestsTotalUnread + onlyMostRecentAcceptedTotalUnread)
        // view context save here?? or on close / app background..
    }
}

struct DMRow: View {
    @ObservedObject var recentDM:Event
    let pubkey:String // own account pubkey
    var unread:Int?
    
    var contact:Contact? {
        // contact is in .pubkey or in .firstP (depending on incoming/outgoing DM.)
        if recentDM.pubkey == self.pubkey, let firstP = recentDM.firstP() {
            return recentDM.contacts?.first(where: { $0.pubkey == firstP })
        }
        else {
            return recentDM.contact
        }
    }
    
    var contactPubkey:String {
        // pubkey is .pubkey or .firstP (depending on incoming/outgoing DM.)
        if recentDM.pubkey == self.pubkey, let firstP = recentDM.firstP() {
            return firstP
        }
        else {
            return recentDM.pubkey
        }
    }
    
    var body: some View {
        HStack(alignment: .top) {
            ZStack {
                PFP(pubkey: contactPubkey, contact: contact)
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
                            
                            // TODO: FIXX WEIRD:
                            if let contact = contact {
                                NameAndNip(contact: NRContact(contact: contact))
                            }
                            
                            Group {
                                Text("@\(contact?.username ?? String(npub(contactPubkey).prefix(11)))").layoutPriority(1)
                                Text(" · ") //
                                Ago(recentDM.date).layoutPriority(1) //
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(recentDM.noteText).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct DirectMessages_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DirectMessages(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", blockedPubkeys: [])
        }
        .withPreviewEnvironment()
    }
}
