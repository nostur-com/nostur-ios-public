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
import NostrEssentials

struct ProfileView: View {
    @StateObject private var vm = ProfileViewModel()
    @StateObject private var lastSeenVM = LastSeenViewModel()
    
    @ObservedObject public var nrContact: NRContact
    public var tab: String?
    
    
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @EnvironmentObject private var la: LoggedInAccount
    
    @ObservedObject private var settings: SettingsStore = .shared

//    @State private var profilePicViewerIsShown = false
    @State private var selectedSubTab = "Posts"

    @State private var editingAccount: CloudAccount?
    
    @State private var scrollPosition = NXScrollPosition()
    
    @State private var showFollowing = false
    @State private var showFollowers = false
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        List {
            Section {
                VStack(alignment: .leading) {
                    
                    ProfileBanner(banner: nrContact.banner, width: availableWidth)
                        .overlay(alignment: .bottomLeading, content: {
                            self.pfpView
                        })
                    
                    self.firstRowItemsView

                    HStack(spacing: 0) {
                        Text("\(nrContact.anyName) ")
                            .font(.title)
                            .fontWeightBold()
                            .lineLimit(1)
                        PossibleImposterLabelView2(nrContact: nrContact)
                        if nrContact.similarToPubkey == nil && nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
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
                                sendNotification(.addRemoveToListsheet, nrContact)
                            } label: {
                                Label(String(localized:"Add/Remove from Lists", comment:"Menu action"), systemImage: "person.2.crop.square.stack")
                            }
                            
                            if vm.isBlocked {
                                Button(action: {
                                    unblock(pubkey: nrContact.pubkey)
                                    vm.isBlocked = false // TODO: Add listener on vm instead of this
                                }) {
                                    Label("Unblock", systemImage: "circle.slash")
                                }
                            }
                            else {
                                Button {
                                    block(pubkey: nrContact.pubkey, name: nrContact.anyName)
                                    vm.isBlocked = true // TODO: Add listener on vm instead of this
                                } label: {
                                    Label(
                                        String(localized:"Block \(nrContact.anyName)", comment: "Menu action"), systemImage: "circle.slash")
                                }
                            }
                            Button {
                                sendNotification(.reportContact, ReportContact(nrContact: nrContact))
                            } label: {
                                Label(String(localized:"Report \(nrContact.anyName)", comment:"Menu action"), systemImage: "flag")
                            }
                            
                            Button {
                                vm.copyProfileSource(nrContact)
                            } label: {
                                Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
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
                            .onTapGesture {
                                showFollowing = true
                            }
                        Text("**♾️** Followers", comment: "Label for followers count")
                            .onTapGesture {
                                showFollowers = true
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
            .background(theme.listBackground)
            
            self.subTabsView
        }
        .background(theme.listBackground)
        .listRowInsets(EdgeInsets())
        .listStyle(.plain)
        .modifier {
            if AVAILABLE_26 {
                $0.overlay(alignment: .top) {
                    ProfileToolbar(pubkey: nrContact.pubkey, nrContact: nrContact, scrollPosition: scrollPosition, editingAccount: $editingAccount)
                        .frame(height: 51)
                        .padding(.leading, 70)
                        .padding(.trailing, 10)
                        .clipped()
                        .padding(.top, 55)
                        .edgesIgnoringSafeArea(.top)
                }
            }
            else {
                $0.toolbar {
                    ProfileToolbar(pubkey: nrContact.pubkey, nrContact: nrContact, scrollPosition: scrollPosition, editingAccount: $editingAccount)
                  }
                  .overlay(alignment: .bottomTrailing) { // On 26.0 the new post button is integrated in the new tab bar (or in the custom tabbar on Tahoe)
                      NewPostButton(action: {
                          AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .textNote, directMention: nrContact)
                      })
                      .padding([.top, .leading, .bottom], 10)
                      .padding([.trailing], 25)
                      .buttonStyleGlassProminent()
                   }
            }
        }
        .sheet(item: $editingAccount) { account in
            NBNavigationStack {
                AccountEditView(account: account)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }

        
        .nbNavigationDestination(isPresented: $showFollowing) {
            ProfileFollowingList(pubkey: nrContact.pubkey)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen usage (for bg)
                .navigationTitle("Following")
                .background(theme.listBackground)
                .environment(\.containerID, containerID)
        }
        .nbNavigationDestination(isPresented: $showFollowers) {
            NXList(plain: true) {
                FollowersList(pubkey: nrContact.pubkey)
            }
            .navigationTitle("Followers")
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen usage (for bg)
            .background(theme.listBackground)
            .environment(\.containerID, containerID)
        }
        
        .onAppear {
            if let tab = tab {
                selectedSubTab = tab
            }
            vm.load(nrContact)
            lastSeenVM.checkLastSeen(nrContact.pubkey)
        }
        
        .task {
            try? await Task.sleep(nanoseconds: 5_100_000_000) // Try .SEARCH relays if we don't have info
            if nrContact.metadata_created_at == 0 {
                nxReq(Filters(authors: [nrContact.pubkey], kinds: [0]), subscriptionId: UUID().uuidString, relayType: .SEARCH)
            }
        }
    }
    
    @ViewBuilder
    var pfpView: some View {
        ZoomableItem({
            PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: DIMENSIONS.PFP_BIG)
                .overlay(
                    Circle()
                        .strokeBorder(theme.listBackground, lineWidth: 3)
                )
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: NXScrollOffset.self, value: geometry.frame(in: .global).origin)
                    }
                }
                .onPreferenceChange(NXScrollOffset.self) { position in
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
                    .strokeBorder(theme.listBackground, lineWidth: 3)
            }
        }
        .allowsHitTesting(nrContact.pictureUrl != nil)
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
    }
    
    @ViewBuilder
    var firstRowItemsView: some View {
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
                            .background(theme.listBackground)
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
                            .background(theme.listBackground)
                            .border(theme.listBackground, width: 2.0)
                            .offset(y: -3)
                    }
                    .offset(y: 3)
                    .onTapGesture { vm.toggleNewPostNotifications(nrContact.pubkey) }
                    .padding([.trailing, .top], 5)
            }
            
            
            if account()?.isFullAccount ?? false {
                Button {
                    goToDMs()
                    guard let account = account() else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        sendNotification(.triggerDM, NewDMConversation(accountPubkey: account.publicKey, participants: Set([account.publicKey,nrContact.pubkey]), parentDMsVM: DMsVM.shared))
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
        }    }
    
    @ViewBuilder
    var subTabsView: some View {
        Section(content: {
            switch selectedSubTab {
            case "Posts":
                if let pinnedPost = vm.pinnedPost {
                    Box(nrPost: pinnedPost) {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .fontWeightBold()
                                    .scaleEffect(0.6)
                                    .layoutPriority(1)
                                
                                Text("Pinned")
                                    .lineLimit(1)
                                    .font(.subheadline)
                                    .fontWeightBold()
                            }
                            .foregroundColor(.gray)
                            .padding(.leading, 36)
                            PostRowDeletable(nrPost: pinnedPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, ignoreBlock: true, theme: theme)
                                .environment(\.pinnedPostId, pinnedPost.id)
                        }
                    }
                }
                ProfilePostsView(pubkey: nrContact.pubkey, type: .posts)
                    .background(theme.listBackground)
            case "Replies":
                ProfilePostsView(pubkey: nrContact.pubkey, type: .replies)
                    .background(theme.listBackground)
            case "Highlights":
                ProfileHighlights(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case "Lists":
                ProfilePostsView(pubkey: nrContact.pubkey, type: .lists)
                    .background(theme.listBackground)
            case "Articles":
                ProfilePostsView(pubkey: nrContact.pubkey, type: .articles)
                    .background(theme.listBackground)
            case "Interactions":
                ProfileInteractionsView(nrContact: nrContact)
                    .background(theme.listBackground)
            case "Media":
                ProfileMediaView(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case "Reactions":
                ProfileReactionsView(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case "Zaps":
                ProfileZapsView(nrContact: nrContact)
                    .background(theme.listBackground)
            case "Relays":
                ProfileRelays(pubkey: nrContact.pubkey, name: nrContact.anyName)
                    .background(theme.listBackground)
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
                    if vm.showHighlightsTab {
                        TabButton(
                            action: { selectedSubTab = "Highlights" },
                            title: String(localized: "Highlights", comment:"Tab title"),
                            selected: selectedSubTab == "Highlights")
                        Spacer()
                    }
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
                    if nrContact.pubkey != AccountsState.shared.activeAccountPublicKey {
                        TabButton(
                            action: { selectedSubTab = "Interactions" },
                            title: String(localized: "Interactions", comment:"Tab title"),
                            selected: selectedSubTab == "Interactions")
                        Spacer()
                    }
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
                .frame(minWidth: availableWidth)
            }
            .frame(width: availableWidth)
            .listRowInsets(.init())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        })
        .listRowInsets(EdgeInsets())
        .listSectionSeparator(.hidden)
        .listRowSeparator(.hidden)
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

class NXScrollPosition: ObservableObject {
    @Published var position: CGPoint = .zero
}

struct NXScrollOffset: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { }
}
