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
    @StateObject private var vm = ProfileViewModel()
    @StateObject private var lastSeenVM = LastSeenViewModel()
    
    @ObservedObject public var nrContact: NRContact
    public var tab: String?
    
    
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var la: LoggedInAccount
    
    @ObservedObject private var settings: SettingsStore = .shared

//    @State private var profilePicViewerIsShown = false
    @State private var selectedSubTab = "Posts"

    @State private var editingAccount: CloudAccount?
    @State private var showingNewNote = false
    
    @State private var scrollPosition = ScrollPosition()
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        List {
            Section {
                VStack(alignment: .leading) {
                    
                    ProfileBanner(banner: nrContact.banner, width: dim.listWidth)
                        .overlay(alignment: .bottomLeading, content: {
                            ZoomableItem({
                                PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: DIMENSIONS.PFP_BIG)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(themes.theme.listBackground, lineWidth: 3)
                                    )
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear
                                                .preference(key: ScrollOffset.self, value: geometry.frame(in: .global).origin)
                                        }
                                    }
                                    .onPreferenceChange(ScrollOffset.self) { position in
                                        self.scrollPosition.position = position
                                    }
                            }, frameSize: CGSize(width: DIMENSIONS.PFP_BIG, height: DIMENSIONS.PFP_BIG)) {
                                if let pictureUrl = nrContact.pictureUrl {
                                    GalleryFullScreenSwiper(
                                        initialIndex: 0,
                                        items: [GalleryItem(url: pictureUrl)],
                                        usePFPpipeline: false // false or we only get 50x50 version scaled up blurry
                                    )
                                }
                                else {
                                    Circle()
                                        .strokeBorder(themes.theme.listBackground, lineWidth: 3)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if let fixedPfp = vm.fixedPfp {
                                    ZoomableItem({
                                        FixedPFP(picture: fixedPfp)
                                    }, frameSize: .init(width: 20.0, height: 20.0)) {
                                        GalleryFullScreenSwiper(
                                            initialIndex: 0,
                                            items: [GalleryItem(url: fixedPfp)],
                                            usePFPpipeline: true // needs to be from pfp cache, will be blurry scaled up but too bad
                                        )
                                    }
                                }
                            }
                            .offset(y: DIMENSIONS.PFP_BIG/2)
                        })
                    
                    HStack(alignment: .top) {
                        if (!settings.hideBadges) {
                            ProfileBadgesContainer(pubkey: nrContact.pubkey)
                                .offset(x: 85, y: 0)
                        }
                        
                        Spacer()
                        
                        if vm.newPostsNotificationsEnabled {
                            Image(systemName: "bell")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .resizable()
                                        .frame(width: 10, height: 10)
                                        .foregroundColor(.green)
                                        .background(themes.theme.listBackground)
                                        .offset(y: -3)
                                }
                                .offset(y: 3)
                                .onTapGesture { vm.toggleNewPostNotifications(nrContact.pubkey) }
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
                                        .background(themes.theme.listBackground)
                                        .border(themes.theme.listBackground, width: 2.0)
                                        .offset(y: -3)
                                }
                                .offset(y: 3)
                                .onTapGesture { vm.toggleNewPostNotifications(nrContact.pubkey) }
                                .padding([.trailing, .top], 5)
                        }
                        
                        
                        if account()?.isFullAccount ?? false {
                            Button {
                                UserDefaults.standard.setValue("Messages", forKey: "selected_tab")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    sendNotification(.triggerDM, (nrContact.pubkey, nrContact))
                                }
                            } label: { Image(systemName: "envelope.fill") }
                                .buttonStyle(NosturButton())
                        }
                        
                        if nrContact.anyLud {
                            ProfileLightningButton(nrContact: nrContact)
                        }
                        
                        if nrContact.pubkey == AccountsState.shared.activeAccountPublicKey {
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
                        }
                    }

                    HStack(spacing: 0) {
                        Text("\(nrContact.anyName) ")
                            .font(.title)
                            .fontWeightBold()
                            .lineLimit(1)
                        NewPossibleImposterLabel(nrContact: nrContact)
                        if nrContact.similarToPubkey == nil && nrContact.nip05verified, let nip05 = nrContact.nip05 {
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
                    
                    HStack {
                        CopyableTextView(text: vm.npub)
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)
                        
                        if let mainContact = Contact.fetchByPubkey(nrContact.pubkey, context: viewContext())  {
                            ContactPrivateNoteToggle(contact: mainContact)
                        }
                        Menu {
                            Button {
                                UIPasteboard.general.string = vm.npub
                            } label: {
                                Label(String(localized:"Copy npub", comment:"Menu action"), systemImage: "doc.on.clipboard")
                            }
                            Button {
                                vm.copyProfileSource(nrContact)
                            } label: {
                                Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
                            }
                            Button {
                                sendNotification(.addRemoveToListsheet, nrContact)
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
                                sendNotification(.reportContact, ReportContact(nrContact: nrContact))
                            } label: {
                                Label(String(localized:"Report \(nrContact.anyName)", comment:"Menu action"), systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .fontWeightBold()
                                .padding(5)
                        }
                        
                        if (vm.isFollowingYou) {
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
                    
                    Text(verbatim: lastSeenVM.lastSeen ?? "Last seen:")
                        .font(.caption).foregroundColor(.primary)
                        .lineLimit(1)
                        .opacity(lastSeenVM.lastSeen != nil ? 1.0 : 0)
                    
                    NRTextDynamic("\(String(nrContact.about ?? ""))\n")
                    
                    HStack(alignment: .center, spacing: 10) {
                        ProfileFollowingCount(pubkey: nrContact.pubkey)
                        
                        Text("**♾️** Followers", comment: "Label for followers count")
                            .onTapGesture {
                                selectedSubTab = "Followers"
                            }
                    }
                    .frame(height: 30)
                    
                    FollowedBy(pubkey: nrContact.pubkey, showHeaderText: false)
                }
                .padding([.top, .leading, .trailing], 10.0)
                .onTapGesture { }
            }
            .listRowInsets(EdgeInsets())
            .lineSpacing(0)
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
            .background(themes.theme.listBackground)
            
            Section(content: {
                switch selectedSubTab {
                case "Posts":
                    ProfilePostsView(pubkey: nrContact.pubkey, type: .posts)
                        .background(themes.theme.listBackground)
                case "Replies":
                    ProfilePostsView(pubkey: nrContact.pubkey, type: .replies)
                        .background(themes.theme.listBackground)
                case "Lists":
                    ProfilePostsView(pubkey: nrContact.pubkey, type: .lists)
                        .background(themes.theme.listBackground)
                case "Articles":
                    ProfilePostsView(pubkey: nrContact.pubkey, type: .articles)
                        .background(themes.theme.listBackground)
                case "Interactions":
                    ProfileInteractionsView(nrContact: nrContact)
                        .background(themes.theme.listBackground)
                case "Following":
                    ProfileFollowingList(pubkey: nrContact.pubkey)
                        .background(themes.theme.listBackground)
                case "Media":
                    ProfileMediaView(pubkey: nrContact.pubkey)
                        .background(themes.theme.listBackground)
                case "Reactions":
                    ProfileReactionsView(pubkey: nrContact.pubkey)
                        .background(themes.theme.listBackground)
                case "Zaps":
                    ProfileZapsView(nrContact: nrContact)
                        .background(themes.theme.listBackground)
                case "Relays":
                    ProfileRelays(pubkey: nrContact.pubkey, name: nrContact.anyName)
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
                            title: String(localized: "Posts", comment:"Tab title"),
                            selected: selectedSubTab == "Posts")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Replies" },
                            title: String(localized: "Replies", comment:"Tab title"),
                            selected: selectedSubTab == "Replies")
                        Spacer()
                        if vm.showListsTab {
                            TabButton(
                                action: { selectedSubTab = "Lists" },
                                title: String(localized: "Lists", comment:"Tab title"),
                                selected: selectedSubTab == "Lists")
                            Spacer()
                        }
                        if vm.showArticlesTab {
                            TabButton(
                                action: { selectedSubTab = "Articles" },
                                title: String(localized: "Articles", comment:"Tab title"),
                                selected: selectedSubTab == "Articles")
                            Spacer()
                        }
                        TabButton(
                            action: { selectedSubTab = "Interactions" },
                            title: String(localized: "Interactions", comment:"Tab title"),
                            selected: selectedSubTab == "Interactions")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Following" },
                            title: String(localized: "Following", comment:"Tab title"),
                            selected: selectedSubTab == "Following")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Media" },
                            title: String(localized: "Media", comment:"Tab title"),
                            selected: selectedSubTab == "Media")
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Reactions" },
                            title: String(localized: "Reactions", comment:"Tab title"),
                            selected: selectedSubTab == "Reactions")
                        Spacer()
                        if #available(iOS 16.0, *) {
                            TabButton(
                                action: { selectedSubTab = "Zaps" },
                                title: String(localized: "Zaps", comment:"Tab title"),
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
                .listRowInsets(.init())
                .listSectionSeparator(.hidden)
                .listRowSeparator(.hidden)
            })
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        }
        .background(themes.theme.listBackground)
        .listRowInsets(EdgeInsets())
        .listStyle(.plain)
        .toolbar {
            ProfileToolbar(pubkey: nrContact.pubkey, nrContact: nrContact, scrollPosition: scrollPosition, editingAccount: $editingAccount, themes: themes)
        }
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
                            ComposePost(directMention: nrContact, onDismiss: { showingNewNote = false })
                                .environmentObject(themes)
                                .environmentObject(la)
//                                .environmentObject(screenSpace)
                        }
                    }
                    else {
                        ComposePost(directMention: nrContact, onDismiss: { showingNewNote = false })
                            .environmentObject(themes)
                            .environmentObject(la)
//                            .environmentObject(screenSpace)
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .onAppear {
            if let tab = tab {
                selectedSubTab = tab
            }
            vm.load(nrContact)
            lastSeenVM.checkLastSeen(nrContact.pubkey)
//            imposterVM.runCheck(nrContact)
        }
        .onChange(of: nrContact.nip05) { nip05 in
            bg().perform {
                guard let contact = nrContact.contact, NIP05Verifier.shouldVerify(contact) else { return }
                NIP05Verifier.shared.verify(contact)
            }
        }
    }
}



#Preview("ProfileView - snowden") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NRNavigationStack {
            if let contact = PreviewFetcher.fetchNRContact("84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240") {
                Zoomable {
                    ProfileView(nrContact: contact)
                }
            }
        }
    }
}

#Preview("ProfileView - fabian") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NRNavigationStack {
            if let contact = PreviewFetcher.fetchNRContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                
                let _ = contact.nip05 = "fabian@nostur.com"
                let _ = contact.nip05nameOnly = "fabian"
                let _ = contact.nip05verified = true
                
                Zoomable {
                    ProfileView(nrContact: contact)
                }
            }
        }
    }
}

class ScrollPosition: ObservableObject {
    @Published var position: CGPoint = .zero
}

struct ScrollOffset: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { }
}
