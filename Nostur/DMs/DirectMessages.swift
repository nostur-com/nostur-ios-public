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
            if account.isNC {
                Text("Direct Messages using a nsecBunker login are not available yet")
                    .centered()
            }
            else {
                DirectMessages(pubkey: account.publicKey, blockedPubkeys: account.blockedPubkeys_)
            }
        }
        else {
            EmptyView()
        }
    }
}

struct DirectMessages: View {
    @EnvironmentObject var nm:NotificationsManager
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
//        let _ = Self._printChanges()
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
                                        Text("Accepted", comment: "Tab title for accepted DMs (Direct Messages)").lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .padding(.top, 8)
                                            .padding(.bottom, 5)
                                        if onlyMostRecentAcceptedTotalUnread > 0 {
                                            Menu {
                                                Button { markAllAsRead() } label: {
                                                    Label(String(localized: "Mark all as read", comment:"Menu action to mark all messages as read"), systemImage: "envelope.open")
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
                            }, title: String(localized: "Requests", comment: "Tab title for DM (Direct Message) requests"), selected: tab == "Requests", unread: requestsTotalUnread)
                        }
                        switch (tab) {
                        case "Accepted":
                            if !onlyMostRecentAccepted.isEmpty {
                                List(onlyMostRecentAcceptedFiltered, id:\.0) { (dm, unread) in
                                    NavigationLink(value: dm) {
                                        DMRow(recentDM: dm, pubkey: pubkey, unread: unread)
                                    }
                                }
                                .listStyle(.plain)
                                .onAppear {
                                    sendNotification(.updateDMsCount, (requestsTotalUnread + onlyMostRecentAcceptedTotalUnread))
                                }
                            }
                            else {
                                Text("You have not received any messages", comment: "Shown on the DM view when there aren't any direct messages to show")
                                    .centered()
                            }
                        case "Requests":
                            if !onlyMostRecentRequests.isEmpty {
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
                                Text("No message requests", comment: "Shown on the DM requests view when there aren't any message requests to show")
                                    .centered()
                            }
                        default:
                            EmptyView()
                        }
                        
                    }
                    NewDMButton(showingNewDM: $showingNewDM)
                }
                Text("Note: The contents of DMs is encrypted but the metadata is not. Who you send a message to and when is public.", comment:"Informational message on the DM screen")
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
            .navigationTitle(String(localized: "Messages", comment: "Navigation title for DMs (Direct Messages)"))
            .navigationBarTitleDisplayMode(.inline)
            .withNavigationDestinations()
        }
        .task {
            req(RM.getAuthorDMs(pubkey: pubkey))
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
        sendNotification(.updateDMsCount, requestsTotalUnread)
        onlyMostRecentAll.filter { $0.value.1 == true && $0.value.2 > 0 }
            .forEach { (key: String, value: ([Event], Bool, Int, Int64, Event)) in
                if let last = value.0.last {
                    let rootDM = value.4
                    rootDM.objectWillChange.send()
                    rootDM.lastSeenDMCreatedAt = last.created_at
                }
            }
        DataProvider.shared().save()
    }
    
    func updateLastSeenDMRequestCreatedAt() {
        guard let account = ns.account else { return }
        guard let latestRootDMcreatedAt = onlyMostRecentRequests.map({ $0.1 }).max() else { return }
        
        account.lastSeenDMRequestCreatedAt = latestRootDMcreatedAt
        sendNotification(.updateDMsCount, onlyMostRecentAcceptedTotalUnread)
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
                    .onAppear {
                        if contact?.metadata_created_at == 0 {
                            EventRelationsQueue.shared.addAwaitingEvent(recentDM)
                            QueuedFetcher.shared.enqueue(pTag: contactPubkey)
                        }
                    }
                    .onDisappear {
                        if contact?.metadata_created_at == 0 {
                            QueuedFetcher.shared.dequeue(pTag: contactPubkey)
                        }
                    }
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
                                NameAndNip(contact: NRContact(contact: contact))
                            }
                            else {
                                EmptyView()
                                    .onAppear {
                                        EventRelationsQueue.shared.addAwaitingEvent(recentDM)
                                        QueuedFetcher.shared.enqueue(pTag: contactPubkey)
                                    }
                                    .onDisappear {
                                        QueuedFetcher.shared.dequeue(pTag: contactPubkey)
                                    }
                            }
                            Ago(recentDM.date).layoutPriority(1)
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
        PreviewContainer({ pe in pe.loadDMs() }) {
            NavigationStack {
                DirectMessages(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", blockedPubkeys: [])
            }
        }
    }
}
