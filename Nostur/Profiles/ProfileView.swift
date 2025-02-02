//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import NavigationBackport

struct ProfileView: View {
    private let pubkey: String
    private var tab: String?
    
    @EnvironmentObject private var npn: NewPostNotifier
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var fg: FollowingGuardian = .shared
    @ObservedObject private var nrContact: NRContact
    
    @State private var profilePicViewerIsShown = false
    @State private var selectedSubTab = "Posts"
    @State private var backlog = Backlog(timeout: 4.0, auto: true)
    @State private var lastSeen: String? = nil
    @State private var isFollowingYou = false
    @State private var editingAccount: CloudAccount?
    @State private var similarPFP = false
    @State private var showingNewNote = false
    @State private var fixedPfp: URL?
    @State private var npub = ""
    
    @State private var showArticlesTab = false
    
    @State private var scrollPosition = ScrollPosition()
    
    init(nrContact: NRContact, tab: String? = nil) {
        self.nrContact = nrContact
        self.pubkey = nrContact.pubkey
        self.tab = tab
    }
    
    var couldBeImposter: Bool {
        guard let la = NRState.shared.loggedInAccount else { return false }
        guard la.account.publicKey != pubkey else { return false }
        guard !la.isFollowing(pubkey: pubkey) else { return false }
        guard nrContact.couldBeImposter == -1 else { return nrContact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        List {
            Section {
                VStack(alignment: .leading) {
                    
                    ProfileBanner(banner: nrContact.banner, width: dim.listWidth)
                        .overlay(alignment: .bottomLeading, content: {
                            PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: DIMENSIONS.PFP_BIG)
                                .overlay(
                                    Circle()
                                        .strokeBorder(themes.theme.background, lineWidth: 3)
                                )
                                .onTapGesture {
                                    if (nrContact.pictureUrl != nil) {
                                        profilePicViewerIsShown = true
                                    }
                                }
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear
                                            .preference(key: ScrollOffset.self, value: geometry.frame(in: .global).origin)
                                    }
                                }
                                .onPreferenceChange(ScrollOffset.self) { position in
                                    self.scrollPosition.position = position
                                }
                            //                            .scaleEffect(min(1,max(0.5,geoBanner.frame(in:.global).minY / 70 + 1.3)), anchor:.bottom)
                                .overlay(alignment: .bottomTrailing) {
                                    if let fixedPfp {
                                        FixedPFP(picture: fixedPfp)
                                    }
                                }
                                .offset(x: 10, y: DIMENSIONS.PFP_BIG/2)
                        })
                    
                    HStack(alignment: .top) {
                        if (!settings.hideBadges) {
                            ProfileBadgesContainer(pubkey: nrContact.pubkey)
                                .offset(x: 85, y: 0)
                        }
                        
                        Spacer()
                        
                        if npn.isEnabled(for: nrContact.pubkey) {
                            Image(systemName: "bell")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .resizable()
                                        .frame(width: 10, height: 10)
                                        .foregroundColor(.green)
                                        .background(themes.theme.background)
                                        .offset(y: -3)
                                }
                                .offset(y: 3)
                                .onTapGesture { npn.toggle(nrContact.pubkey) }
                                .padding([.trailing, .top], 5)
                        }
                        else {
                            Image(systemName: "bell")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "plus")
                                        .resizable()
                                        .frame(width: 10, height: 10)
                                        .background(themes.theme.background)
                                        .border(themes.theme.background, width: 2.0)
                                        .offset(y: -3)
                                }
                                .offset(y: 3)
                                .onTapGesture { npn.toggle(nrContact.pubkey) }
                                .padding([.trailing, .top], 5)
                        }
                        
                        
                        if account()?.isFullAccount ?? false {
                            Button {
                                UserDefaults.standard.setValue("Messages", forKey: "selected_tab")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    sendNotification(.triggerDM, (nrContact.pubkey, nrContact.mainContact))
                                }
                            } label: { Image(systemName: "envelope.fill") }
                                .buttonStyle(NosturButton())
                        }
                        
                        if nrContact.anyLud {
                            ProfileLightningButton(contact: nrContact.mainContact)
                        }
                        
                        if pubkey == NRState.shared.activeAccountPublicKey {
                            Button {
                                guard let account = account() else { return }
                                guard isFullAccount(account) else { showReadOnlyMessage(); return }
                                editingAccount = account
                            } label: {
                                Text("Edit profile", comment: "Button to edit own profile")
                            }
                            .buttonStyle(NosturButton())
                        }
                        else {
                            FollowButton(pubkey: nrContact.pubkey)
                            .buttonStyle(.borderless)
                            .padding(.trailing, 10)
                        }
                    }
                    
                    HStack(spacing: 0) {
                        Text("\(nrContact.anyName) ").font(.system(size: 24, weight:.bold))
                        if couldBeImposter {
                            PossibleImposterLabel(possibleImposterPubkey: nrContact.pubkey, followingPubkey: nrContact.similarToPubkey)
                        }
                        else if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
                        }
                    }
                    
                    if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                        HStack {
                            Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                .lineLimit(1)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    nrContact.setFixedName(nrContact.anyName)
                                }
                        }
                    }
                    
                    CopyableTextView(text: npub)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)
                    
                    Text(verbatim: lastSeen ?? "Last seen:")
                        .font(.caption).foregroundColor(.primary)
                        .lineLimit(1)
                        .opacity(lastSeen != nil ? 1.0 : 0)
                    
                    HStack {
                        if let mainContact = nrContact.mainContact {
                            ContactPrivateNoteToggle(contact: mainContact)
                        }
                        Menu {
                            Button {
                                UIPasteboard.general.string = self.npub
                            } label: {
                                Label(String(localized:"Copy npub", comment:"Menu action"), systemImage: "doc.on.clipboard")
                            }
                            Button {
                                bg().perform {
                                    let kind0 = Event.fetchRequest()
                                    kind0.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                                    kind0.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", nrContact.pubkey)
                                    
                                    if let event = try? bg().fetch(kind0).first {
                                        let json = event.toNEvent().eventJson()
                                        DispatchQueue.main.async {
                                            UIPasteboard.general.string = json
                                        }
                                    }
                                }
                            } label: {
                                Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
                            }
                            
                            Button {
                                sendNotification(.addRemoveToListsheet, nrContact.mainContact)
                            } label: {
                                Label(String(localized:"Add/Remove from feeds", comment:"Menu action"), systemImage: "person.2.crop.square.stack")
                            }
                            
                            
                            Button {
                                block(pubkey: nrContact.pubkey, name: nrContact.anyName)
                            } label: {
                                Label(
                                    String(localized:"Block \(nrContact.anyName)", comment:"Menu action"), systemImage: "slash.circle")
                            }
                            Button {
                                sendNotification(.reportContact, nrContact.mainContact)
                            } label: {
                                Label(String(localized:"Report \(nrContact.anyName)", comment:"Menu action"), systemImage: "flag")
                            }
                            
                            
                        } label: {
                            Image(systemName: "ellipsis")
                                .fontWeightBold()
                                .padding(5)
                        }
                        if (isFollowingYou) {
                            Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.secondary)
                                .opacity(0.7)
                                .cornerRadius(13)
                                .offset(y: -4)
                        }
                    }
                    
                    NRTextDynamic("\(String(nrContact.about ?? ""))\n")
                    
                    HStack(alignment: .center, spacing: 10) {
                        ProfileFollowingCount(pubkey: pubkey)
                        
                        Text("**♾️** Followers", comment: "Label for followers count")
                            .onTapGesture {
                                selectedSubTab = "Followers"
                            }
                    }
                    .frame(height: 30)
                }
                .padding(10)
                .onTapGesture { }
            }
            .listRowInsets(EdgeInsets())
            .lineSpacing(0)
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            .listRowSpacing(10.0)
            .background(themes.theme.background)
            
            Section(content: {
                switch selectedSubTab {
                case "Posts":
                    ProfilePostsView(pubkey: pubkey, type: .posts)
                        .background(themes.theme.listBackground)
                case "Replies":
                    ProfilePostsView(pubkey: pubkey, type: .replies)
                        .background(themes.theme.listBackground)
                case "Articles":
                    ProfilePostsView(pubkey: pubkey, type: .articles)
                        .background(themes.theme.listBackground)
                case "Following":
                    ProfileFollowingList(pubkey: pubkey)
                        .background(themes.theme.listBackground)
                case "Media":
                    ProfileMediaView(pubkey: pubkey)
                        .background(themes.theme.listBackground)
                case "Likes":
                    ProfileLikesView(pubkey: pubkey)
                        .background(themes.theme.listBackground)
                case "Zaps":
                    if #available(iOS 16.0, *), let mainContact = nrContact.mainContact {
                        ProfileZaps(pubkey: pubkey, contact: mainContact)
                            .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                            .background(themes.theme.listBackground)
                    }
                    else {
                        EmptyView()
                    }
                case "Relays":
                    ProfileRelays(pubkey: pubkey, name: nrContact.anyName)
                        .background(themes.theme.listBackground)
                case "Followers":
                    FollowersList(pubkey: nrContact.pubkey)
                        .background(themes.theme.listBackground)
                default:
                    Text("🥪")
                }
            }, header: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        TabButton(
                            action: { selectedSubTab = "Posts" },
                            title: String(localized:"Posts", comment:"Tab title"),
                            selected: selectedSubTab == "Posts")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Replies" },
                            title: String(localized:"Replies", comment:"Tab title"),
                            selected: selectedSubTab == "Replies")
                        Spacer()
                        if showArticlesTab {
                            TabButton(
                                action: { selectedSubTab = "Articles" },
                                title: String(localized:"Articles", comment:"Tab title"),
                                selected: selectedSubTab == "Articles")
                            Spacer()
                        }
                        TabButton(
                            action: { selectedSubTab = "Following" },
                            title: String(localized:"Following", comment:"Tab title"),
                            selected: selectedSubTab == "Following")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Media" },
                            title: String(localized:"Media", comment:"Tab title"),
                            selected: selectedSubTab == "Media")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Likes" },
                            title: String(localized:"Likes", comment:"Tab title"),
                            selected: selectedSubTab == "Likes")
                        Spacer()
                        if #available(iOS 16.0, *) {
                            TabButton(
                                action: { selectedSubTab = "Zaps" },
                                title: String(localized:"Zaps", comment:"Tab title"),
                                selected: selectedSubTab == "Zaps")
                            Spacer()
                        }
                        TabButton(
                            action: { selectedSubTab = "Relays" },
                            title: "Relays",
                            selected: selectedSubTab == "Relays")
                    }
                    .frame(minWidth: dim.listWidth)
                }
                .frame(width: dim.listWidth)
            })
            .listRowSpacing(10.0)
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        }
        .background(themes.theme.listBackground)
        .listRowSpacing(10.0)
        .listStyle(.plain)
        .toolbar(content: {
            ProfileToolbar(pubkey: pubkey, nrContact: nrContact, scrollPosition: scrollPosition, editingAccount: $editingAccount, themes: themes)
        })
        //        .onReceive(receiveNotification(.newFollowingListFromRelay)) { notification in // TODO: MOVE TO FOLLOWING LIST TAB
        //            let nEvent = notification.object as! NEvent
        //            if nEvent.publicKey == contact.pubkey {
        //                contact.objectWillChange.send()
        //            }
        //        }
        .overlay(alignment: .bottomTrailing) {
            NewNoteButton(showingNewNote: $showingNewNote)
                .padding([.top, .leading, .bottom], 10)
                .padding([.trailing], 25)
        }
        .sheet(item: $editingAccount) { account in
            NBNavigationStack {
                AccountEditView(account: account)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .sheet(isPresented: $showingNewNote) {
            NBNavigationStack {
                if let account = Nostur.account() {
                    if account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePostCompat(directMention: nrContact.mainContact, onDismiss: { showingNewNote = false })
                                .environmentObject(themes)
                        }
                    }
                    else {
                        ComposePostCompat(directMention: nrContact.mainContact, onDismiss: { showingNewNote = false })
                            .environmentObject(themes)
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.background)
        }
        .onAppear {
            if let tab = tab {
                selectedSubTab = tab
            }
        }
        .onChange(of: nrContact.nip05) { [weak nrContact] nip05 in
            bg().perform {
                guard let nrContact, let contact = nrContact.contact else { return }
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
            }
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl: nrContact.pictureUrl!)
                .environmentObject(themes)
        }
        .task { [weak nrContact] in
            guard let nrContact else { return }
            guard !SettingsStore.shared.lowDataMode else { return }
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            
            bg().perform {
                if let fixedPfp = nrContact.contact?.fixedPfp,
                   fixedPfp != nrContact.contact?.picture,
                   let fixedPfpUrl = URL(string: fixedPfp),
                   hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl, size: 20.0))
                {
                    DispatchQueue.main.async {
                        withAnimation {
                            self.fixedPfp = fixedPfpUrl
                        }
                    }
                }
            }
            
            ImposterChecker.shared.runImposterCheck(nrContact: nrContact) { imposterYes in
                self.similarPFP = true
            }
        }
        .task { [weak backlog] in
            guard let backlog else { return }
            let contactPubkey = pubkey
            let reqTask = ReqTask(prefix: "SEEN-", reqCommand: { taskId in
                req(RM.getLastSeen(pubkey: contactPubkey, subscriptionId: taskId))
            }, processResponseCommand: { taskId, _, _ in
                bg().perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            }, timeoutCommand: { taskId in
                bg().perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            })
            
            backlog.add(reqTask)
            reqTask.fetch()
        }
        .task { [weak nrContact, weak backlog] in
            guard let backlog else { return }
            bg().perform { [weak nrContact] in
                guard let nrContact, let contact = nrContact.contact else { return }
                let npub = contact.npub
                DispatchQueue.main.async {
                    self.npub = npub
                }
                EventRelationsQueue.shared.addAwaitingContact(contact)
                if (contact.followsYou()) {
                    DispatchQueue.main.async {
                        isFollowingYou = true
                    }
                }
                
                let task = ReqTask(
                    reqCommand: { [weak contact] (taskId) in
                        guard let contact else { return }
                        req(RM.getUserProfileKinds(pubkey: contact.pubkey, subscriptionId: taskId, kinds: [0,3,30008,10002]))
                    },
                    processResponseCommand: { [weak contact] (taskId, _, _) in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    isFollowingYou = true
                                }
                            }
                        }
                    },
                    timeoutCommand: { [weak contact] taskId in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    isFollowingYou = true
                                }
                            }
                        }
                    })
                
                backlog.add(task)
                task.fetch()
                
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
                
                guard contact.anyLud else { return }
                let lud16orNil = contact.lud16
                let lud06orNil = contact.lud06
                Task { [weak contact] in
                    do {
                        if let lud16 = lud16orNil, lud16 != "" {
                            let response = try await LUD16.getCallbackUrl(lud16: lud16)
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkeys.insert(zapperPubkey)
                                    L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
                                }
                            }
                        }
                        else if let lud06 = lud06orNil, lud06 != "" {
                            let response = try await LUD16.getCallbackUrl(lud06: lud06)
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkeys.insert(zapperPubkey)
                                    L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
                                }
                            }
                        }
                    }
                    catch {
                        L.og.error("⚡️🔴 problem in lnurlp \(error)")
                    }
                }
            }
        }
        .task { [weak backlog] in
            guard let backlog else { return }
            let contactPubkey = pubkey
            let reqTask = ReqTask(prefix: "HASART-", reqCommand: { taskId in
                req(RM.getUserProfileKinds(pubkey: contactPubkey, subscriptionId: taskId, kinds: [30023]) )
            }, processResponseCommand: { taskId, _, _ in
                bg().perform {
                    if Event.fetchMostRecentEventBy(pubkey: contactPubkey, andKind: 30023, context: bg()) != nil {
                        DispatchQueue.main.async {
                            withAnimation {
                                self.showArticlesTab = true
                            }
                        }
                    }
                }
            }, timeoutCommand: { taskId in
                bg().perform {
                    if Event.fetchMostRecentEventBy(pubkey: contactPubkey, andKind: 30023, context: bg()) != nil {
                        DispatchQueue.main.async {
                            withAnimation {
                                self.showArticlesTab = true
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

struct ProfileToolbar: View {
    public let pubkey: String
    public let nrContact: NRContact
    @ObservedObject var scrollPosition: ScrollPosition
    @Binding var editingAccount: CloudAccount?
    public let themes: Themes
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 2) {
                PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: 25)
                    .overlay(
                        Circle()
                            .strokeBorder(themes.theme.background, lineWidth: 1)
                    )
                Text("\(nrContact.anyName) ").font(.headline)
                
                Spacer()
                
                if pubkey == NRState.shared.activeAccountPublicKey {
                    Button {
                        guard let account = account() else { return }
                        guard isFullAccount(account) else { showReadOnlyMessage(); return }
                        editingAccount = account
                    } label: {
                        Text("Edit profile", comment: "Button to edit own profile")
                    }
                    .buttonStyle(NosturButton())
                    .layoutPriority(2)
                    //                                    .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                }
                else {
                    FollowButton(pubkey: nrContact.pubkey)
                        .layoutPriority(2)
                    //                                    .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                }
                
            }
            
        }
        .offset(y: max(2, scrollPosition.position.y))
        .frame(height: 40)
        .clipped()
    }
}

#Preview("ProfileView") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let contact = PreviewFetcher.fetchNRContact("84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240") {
                ProfileView(nrContact: contact)
            }
        }
        .nbUseNavigationStack(.never)
    }
}

class ScrollPosition: ObservableObject {
    @Published var position: CGPoint = .zero
}

struct ScrollOffset: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
    }
}
