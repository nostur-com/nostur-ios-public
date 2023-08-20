//
//  Search.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//

import SwiftUI
import Combine

struct Search: View {
    @State var nrPosts:[NRPost] = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var filteredContactSearchResults:[Contact] {
        guard let wot = NosturState.shared.wot else {
            // WoT disabled, just following before non-following
            return contacts
                .sorted(by: { NosturState.shared.followingPublicKeys.contains($0.pubkey) && !NosturState.shared.followingPublicKeys.contains($1.pubkey) })
        }
        return contacts
            // WoT enabled, so put in-WoT before non-WoT
            .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
            // Put following before non-following
            .sorted(by: { NosturState.shared.followingPublicKeys.contains($0.pubkey) && !NosturState.shared.followingPublicKeys.contains($1.pubkey) })
    }

    @State var searching = false
    @AppStorage("selected_tab") var selectedTab = "Search"
    @State var navPath = NavigationPath()

    @State var searchText = ""
    @State var searchTask:Task<Void, Never>? = nil
    @State var backlog = Backlog()
    @ObservedObject var settings:SettingsStore = .shared
    
    var isSearchingHashtag:Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isHashtag(term)
    }

    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            ScrollView {
                if isSearchingHashtag, let account = NosturState.shared.account {
                    FollowHashtagTile(hashtag:String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1)), account:account)
                        .padding([.top, .horizontal], 10)
                }
                if (filteredContactSearchResults.isEmpty && nrPosts.isEmpty && searching) {
                    CenteredProgressView()
                }
                LazyVStack(spacing: 10) {
                    ForEach(filteredContactSearchResults.prefix(75)) { contact in
                        ProfileRow(contact: contact)
                            .background(Color.systemBackground)
                    }
                    ForEach(nrPosts.prefix(75)) { nrPost in
                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true)
                            .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                            .padding(10)
                            .background(Color.systemBackground)
                    }
                }
                .padding(.top, 10)
                .toolbar {
                    if let account = NosturState.shared.account {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                sendNotification(.showSideBar)
                            } label: {
                                PFP(pubkey: account.publicKey, account: account, size:30)
                            }
                            .accessibilityLabel("Account menu")

                        }
                    }
                    ToolbarItem(placement: .principal) {
                        SearchBox(prompt: String(localized: "Search...", comment: "Placeholder text in a search input box"), text: $searchText)
                            .padding(10)
                    }
                }
                .toolbarBackground(Visibility.visible, for: .navigationBar)
            }
            .overlay(alignment: .bottom) {
                if settings.statusBubble {
                    ProcessingStatus()
                        .opacity(0.85)
                        .padding(.bottom, 10)
                }
            }
            .background(Color("ListBackground"))
            .withNavigationDestinations()
            .navigationTitle(String(localized:"Search", comment: "Navigation title for Search screen"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { searchString in
                nrPosts = []
                let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)

                if (searchTrimmed.prefix(9) == "nprofile1") {
                        /// test nevent1qqs0tg4e238wa8ce5yf2fn2t62t3sttwarj5rs557l0n8ftjd308f6qzyrr7mfnq567gyuznp6ptffm39tx75t33ms99d7xuj4dvqz00m97gvqg5waehxw309aex2mrp0yhxgctdw4eju6t0qyf8wumn8ghj7mn0wd68ytnew4mzuctvttk4x8

                    if let identifier = try? ShareableIdentifier(searchTrimmed), let pubkey = identifier.pubkey { // .eventId is already hex
                        searching = true
                        contacts.nsPredicate = NSPredicate(format: "pubkey = %@", pubkey)
                        nrPosts = []
                        req(RM.getUserMetadata(pubkey: pubkey))

                        if !identifier.relays.isEmpty {
                            searchTask = Task {
                                try? await Task.sleep(for: .seconds(3))
                                let ctx = DataProvider.shared().bg
                                await ctx.perform {
                                    // If we don't have the event after X seconds, fetch from relay hint
                                    if Contact.fetchByPubkey(pubkey, context: ctx) == nil {
                                        if let relay = identifier.relays.first {
                                            EphemeralSocketPool.shared.sendMessage(RM.getUserMetadata(pubkey: pubkey), relay: relay)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                else if (searchTrimmed.prefix(6) == "naddr1") {

                    if let naddr = try? ShareableIdentifier(searchTrimmed),
                       let kind = naddr.kind,
                       let pubkey = naddr.pubkey,
                       let definition = naddr.eventId { // .eventId is already hex
                        searching = true
                        contacts.nsPredicate = NSPredicate(value: false)
                        
                        DataProvider.shared().bg.perform {
                            if let article = Event.fetchReplacableEvent(kind,
                                                                             pubkey: pubkey,
                                                                             definition: definition,
                                                                             context: DataProvider.shared().bg) {
                                let article = NRPost(event: article)
                                DispatchQueue.main.async {
                                    self.nrPosts = [article]
                                }
                            }
                            else {
                                let reqTask = ReqTask(
                                    prefix: "ARTICLESEARCH-",
                                    reqCommand: { taskId in
                                        req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition:definition, subscriptionId: taskId))
                                    },
                                    processResponseCommand: { taskId, _ in
                                        DataProvider.shared().bg.perform {
                                            if let article = Event.fetchReplacableEvent(kind,
                                                                                             pubkey: pubkey,
                                                                                             definition: definition,
                                                                                             context: DataProvider.shared().bg) {
                                                let article = NRPost(event: article)
                                                DispatchQueue.main.async {
                                                    self.nrPosts = [article]
                                                }
                                                backlog.clear()
                                            }
                                        }
                                    },
                                    timeoutCommand: { taskId in
                                        if !naddr.relays.isEmpty {
                                            searchTask = Task {
                                                try? await Task.sleep(for: .seconds(3))
                                                let ctx = DataProvider.shared().bg
                                                await ctx.perform {
                                                    // If we don't have the event after X seconds, fetch from relay hint
                                                    if (Event.fetchReplacableEvent(kind, pubkey: pubkey, definition: definition, context: DataProvider.shared().bg)) == nil {
                                                        if let relay = naddr.relays.first {
                                                            EphemeralSocketPool
                                                                .shared
                                                                .sendMessage(
                                                                    RM.getArticle(
                                                                        pubkey: pubkey,
                                                                        kind: Int(kind),
                                                                        definition: definition,
                                                                        subscriptionId: taskId
                                                                    ),
                                                                    relay: relay
                                                                )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    })
                                
                                backlog.add(reqTask)
                                reqTask.fetch()
                            }
                        }
                    }
                }

                else if (searchTrimmed.prefix(7) == "nevent1") {
                        /// test nevent1qqs0tg4e238wa8ce5yf2fn2t62t3sttwarj5rs557l0n8ftjd308f6qzyrr7mfnq567gyuznp6ptffm39tx75t33ms99d7xuj4dvqz00m97gvqg5waehxw309aex2mrp0yhxgctdw4eju6t0qyf8wumn8ghj7mn0wd68ytnew4mzuctvttk4x8

                    if let identifier = try? ShareableIdentifier(searchTrimmed), let noteHex = identifier.eventId { // .eventId is already hex
                        searching = true
                        contacts.nsPredicate = NSPredicate(value: false)
                        
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "id = %@", noteHex)
                        fr.fetchLimit = 1
                        DataProvider.shared().bg.perform {
                            if let result = try? DataProvider.shared().bg.fetch(fr).first {
                                let nrPost = NRPost(event: result)
                                DispatchQueue.main.async {
                                    self.nrPosts = [nrPost]
                                }
                            }
                        }
                        
                        let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
                            req(RM.getEvent(id: noteHex, subscriptionId: taskId))
                        }, processResponseCommand: { taskId, _ in
                            let fr = Event.fetchRequest()
                            fr.predicate = NSPredicate(format: "id = %@", noteHex)
                            fr.fetchLimit = 1
                            DataProvider.shared().bg.perform {
                                if let result = try? DataProvider.shared().bg.fetch(fr).first {
                                    let nrPost = NRPost(event: result)
                                    DispatchQueue.main.async {
                                        self.nrPosts = [nrPost]
                                    }
                                }
                            }
                        })
                        backlog.add(searchTask1)
                        searchTask1.fetch()

                        if !identifier.relays.isEmpty {
                            searchTask = Task {
                                try? await Task.sleep(for: .seconds(3))
                                let ctx = DataProvider.shared().bg
                                await ctx.perform {
                                    // If we don't have the event after X seconds, fetch from relay hint
                                    if (try? Event.fetchEvent(id: noteHex, context: ctx)) == nil {
                                        if let relay = identifier.relays.first {
                                            EphemeralSocketPool.shared.sendMessage(RM.getEvent(id: noteHex, subscriptionId:searchTask1.subscriptionId), relay: relay)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // try npub
                else if (searchTrimmed.prefix(5) == "npub1") {
                    do {
                        searching = true
                        let key = try NIP19(displayString: searchTrimmed)
                        contacts.nsPredicate = NSPredicate(format: "pubkey = %@", key.hexString)
                        nrPosts = []
                        req(RM.getUserMetadata(pubkey: key.hexString))
                    }
                    catch {
                        print("npub1 search fail \(error)")
                        searching = false
                    }
                }

                // try @account
                else if (searchTrimmed.prefix(1) == "@") {
                    searching = true
                    contacts.nsPredicate = NSPredicate(format: "name BEGINSWITH %@", String(searchTrimmed.dropFirst(1)))
                    nrPosts = []
                }
                else if (searchTrimmed.prefix(1) == "#") {
                    searching = true
                    contacts.nsPredicate = NSPredicate(value: false)
                    
                    let fr = Event.fetchRequest()
                    fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                    fr.predicate = NSPredicate(format: "kind == 1 && tagsSerialized CONTAINS %@", serializedT(String(searchTrimmed.dropFirst(1))))
                    fr.fetchLimit = 150
                    DataProvider.shared().bg.perform {
                        if let results = try? DataProvider.shared().bg.fetch(fr) {
                            
                            let nrPosts = results.map { NRPost(event: $0) }
                                .sorted(by: { $0.createdAt > $1.createdAt })
                            
                            DispatchQueue.main.async {
                                self.nrPosts = nrPosts
                            }
                        }
                    }
                    
                    let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
                        req(RM.getHashtag(
                            hashtag: String(searchTrimmed.dropFirst(1)),
                            subscriptionId: taskId
                        ))
                    }, processResponseCommand: { taskId, _ in
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "kind == 1 && tagsSerialized CONTAINS %@", serializedT(String(searchTrimmed.dropFirst(1))))
                        fr.fetchLimit = 150
                        let existingIds = self.nrPosts.map { $0.id }
                        DataProvider.shared().bg.perform {
                            if let results = try? DataProvider.shared().bg.fetch(fr) {
                                let nrPosts = results
                                    .filter { !existingIds.contains($0.id) }
                                    .map { NRPost(event: $0) }

                                DispatchQueue.main.async {
                                    self.nrPosts = (self.nrPosts + nrPosts)
                                        .sorted(by: { $0.createdAt > $1.createdAt })
                                }
                            }
                        }
                    })
                    backlog.add(searchTask1)
                    searchTask1.fetch()
                }
                // try note1
                else if (searchTrimmed.prefix(5) == "note1") {
                    do {
                        searching = true
                        let key = try NIP19(displayString: searchTrimmed)
                        contacts.nsPredicate = NSPredicate(value: false)
                        
                        
                        
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "id = %@", key.hexString)
                        fr.fetchLimit = 1
                        DataProvider.shared().bg.perform {
                            if let result = try? DataProvider.shared().bg.fetch(fr).first {
                                let nrPost = NRPost(event: result)
                                DispatchQueue.main.async {
                                    self.nrPosts = [nrPost]
                                }
                            }
                        }
                        
                        let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
                            req(RM.getEvent(id: key.hexString, subscriptionId: taskId))
                        }, processResponseCommand: { taskId, _ in
                            let fr = Event.fetchRequest()
                            fr.predicate = NSPredicate(format: "id = %@", key.hexString)
                            fr.fetchLimit = 1
                            DataProvider.shared().bg.perform {
                                if let result = try? DataProvider.shared().bg.fetch(fr).first {
                                    let nrPost = NRPost(event: result)
                                    DispatchQueue.main.async {
                                        self.nrPosts = [nrPost]
                                    }
                                }
                            }
                        })
                        backlog.add(searchTask1)
                        searchTask1.fetch()
                        
                        
                    }
                    catch {
                        print("note1 search fail \(error)")
                        searching = false
                    }
                }
                // else try hex id or pubkey
                else if (searchTrimmed.count == 64) {
                    searching = true
                    contacts.nsPredicate = NSPredicate(format: "pubkey = %@", searchTrimmed)
                    req(RM.getUserMetadata(pubkey: searchTrimmed))
                    
                    let fr = Event.fetchRequest()
                    fr.predicate = NSPredicate(format: "id = %@", searchTrimmed)
                    fr.fetchLimit = 1
                    DataProvider.shared().bg.perform {
                        if let result = try? DataProvider.shared().bg.fetch(fr).first {
                            let nrPost = NRPost(event: result)
                            DispatchQueue.main.async {
                                self.nrPosts = [nrPost]
                            }
                        }
                    }
                    
                    let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
                        req(RM.getEvent(id: searchTrimmed, subscriptionId: taskId))
                    }, processResponseCommand: { taskId, _ in
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "id = %@", searchTrimmed)
                        fr.fetchLimit = 1
                        DataProvider.shared().bg.perform {
                            if let result = try? DataProvider.shared().bg.fetch(fr).first {
                                let nrPost = NRPost(event: result)
                                DispatchQueue.main.async {
                                    self.nrPosts = [nrPost]
                                }
                            }
                        }
                    })
                    backlog.add(searchTask1)
                    searchTask1.fetch()
                    
                    
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 5_500_000_000)
                        searching = false
                    }
                }
                // search in names/usernames
                else {
                    searching = false
                    contacts.nsPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@", searchTrimmed, searchTrimmed)
                    
                    let fr = Event.fetchRequest()
                    fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                    fr.predicate = NSPredicate(format: "kind == 1 AND content CONTAINS[cd] %@ AND NOT content BEGINSWITH %@", searchTrimmed, "lnbc")
                    fr.fetchLimit = 150
                    let existingIds = self.nrPosts.map { $0.id }
                    DataProvider.shared().bg.perform {
                        if let results = try? DataProvider.shared().bg.fetch(fr) {
                            let nrPosts = results
                                .filter { !existingIds.contains($0.id) }
                                .map { NRPost(event: $0) }
                            
                            DispatchQueue.main.async {
                                self.nrPosts = (self.nrPosts + nrPosts)
                                    .sorted(by: { $0.createdAt > $1.createdAt })
                            }
                        }
                    }
                }
            }
//            .onAppear {
//                if initialHashtag != "" {
//                    searchText = "#\(initialHashtag ?? "")"
//                }
//            }
            .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
                let importedSubIds = notification.object as! ImportedNotification

                let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)

                reqTasks.forEach { task in
                    task.process()
                }
            }
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard type(of: destination.destination) == Nevent1Path.self || type(of: destination.destination) == Nprofile1Path.self || type(of: destination.destination) == HashtagPath.self || !IS_IPAD else { return }
                guard selectedTab == "Search" else { return }
                if (type(of: destination.destination) == HashtagPath.self) {
                    navPath.removeLast(navPath.count)
                    let hashtag = (destination.destination as! HashtagPath).hashTag
                    searchText = "#\(hashtag)"
                }
                else if (type(of: destination.destination) == Nevent1Path.self) {
                    navPath.removeLast(navPath.count)
                    let nevent1 = (destination.destination as! Nevent1Path).nevent1
                    searchText = nevent1
                }
                else if (type(of: destination.destination) == Nprofile1Path.self) {
                    navPath.removeLast(navPath.count)
                    let nprofile1 = (destination.destination as! Nprofile1Path).nprofile1
                    searchText = nprofile1
                }
                else {
                    navPath.removeLast(navPath.count)
                    navPath.append(destination.destination)
                }
            }
            .onReceive(receiveNotification(.clearNavigation)) { notification in
                navPath.removeLast(navPath.count)
            }
            .simultaneousGesture(
                   DragGesture().onChanged({
                       if 0 < $0.translation.height {
                           sendNotification(.scrollingUp)
                       }
                       else if 0 > $0.translation.height {
                           sendNotification(.scrollingDown)
                       }
                   }))
        }
    }
}

public final class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var bag = Set<AnyCancellable>()

    public init(dueTime: TimeInterval = 0.5) {
        $text
            .removeDuplicates()
            .filter { $0.count > 1 || $0 == "" }
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &bag)
    }
}

struct Search_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
            pe.loadContacts()
        }) {
            NavigationStack {
                Search()
            }
        }
    }
}
