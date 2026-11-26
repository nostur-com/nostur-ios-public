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
    public var usesNativeNavigation = false
    
    
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @EnvironmentObject private var la: LoggedInAccount
    
    @ObservedObject private var settings: SettingsStore = .shared

//    @State private var profilePicViewerIsShown = false
    @State private var selectedSection: ProfileContentSection = .posts
    @State private var interactionKind: ProfileInteractionsView.Kind = .conversations

    @State private var editingAccount: CloudAccount?
    
    @StateObject private var scrollPosition = NXScrollPosition()
    @State private var mainContact: Contact?
    
    @State private var showProfileShare = false
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
                        
                        if let mainContact {
                            ContactPrivateNoteToggle(contact: mainContact)
                        }
                        Menu {
                            Button { showProfileShare = true } label: {
                                Label("Share profile", systemImage: "square.and.arrow.up")
                            }
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
                    
                    NRParsedTextDynamic(text: "\(String(nrContact.about ?? ""))\n")
                    
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
        .sheet(isPresented: $showProfileShare) {
            ProfileShareSheet(pubkey: nrContact.pubkey, name: nrContact.anyName, pictureUrl: nrContact.pictureUrl)
        }
        .sheet(item: $editingAccount) { account in
            NBNavigationStack {
                AccountEditView(account: account)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }

        
        .nosturNavigationDestination(isPresented: $showFollowing, usesNativeNavigation: usesNativeNavigation) {
            ProfileFollowingList(pubkey: nrContact.pubkey)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure full screen usage (for bg)
                .navigationTitle("Following")
                .background(theme.listBackground)
                .environment(\.containerID, containerID)
        }
        .nosturNavigationDestination(isPresented: $showFollowers, usesNativeNavigation: usesNativeNavigation) {
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
                selectedSection = ProfileContentSection(rawValue: tab) ?? .posts
            }
            vm.load(nrContact)
            lastSeenVM.checkLastSeen(nrContact.pubkey)
        }

        .task(id: nrContact.pubkey) {
            mainContact = Contact.fetchByPubkey(nrContact.pubkey, context: viewContext())
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
            ZappablePFP(pubkey: nrContact.pubkey, contact: nrContact, size: DIMENSIONS.PFP_BIG)
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
                    scrollPosition.update(position)
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
                    guard let account = account() else { return }
                    goToDMConversation(NewDMConversation(accountPubkey: account.publicKey, participants: Set([account.publicKey, nrContact.pubkey]), parentDMsVM: DMsVM.shared))
                } label: { Image(systemName: "envelope.fill") }
                    .buttonStyle(NosturButton())
            }

            Button { showProfileShare = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(NosturButton())
            .accessibilityLabel("Share profile")
            
            if nrContact.anyLud {
                ProfileLightningButton(
                    nrContact: nrContact,
                    strikeLocation: scrollPosition.position == .zero ? nil : CGPoint(
                        x: scrollPosition.position.x + (DIMENSIONS.PFP_BIG / 2),
                        y: scrollPosition.position.y + (DIMENSIONS.PFP_BIG / 2)
                    ),
                    sideStrikeWidth: max(0, availableWidth - (DIMENSIONS.PFP_BIG + 20.0))
                )
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
    
    private var showsPersonalInteractions: Bool {
        nrContact.pubkey != AccountsState.shared.activeAccountPublicKey
    }

    private var visibleSection: ProfileContentSection {
        if selectedSection == .withYou, !showsPersonalInteractions {
            return .posts
        }
        return selectedSection
    }

    private var subTabsView: some View {
        Section {
            switch visibleSection {
            case .posts:
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
            case .replies:
                ProfilePostsView(pubkey: nrContact.pubkey, type: .replies)
                    .background(theme.listBackground)
            case .highlights:
                ProfileHighlights(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case .lists:
                ProfilePostsView(pubkey: nrContact.pubkey, type: .lists)
                    .background(theme.listBackground)
            case .articles:
                ProfilePostsView(pubkey: nrContact.pubkey, type: .articles)
                    .background(theme.listBackground)
            case .withYou:
                ProfileInteractionsView(nrContact: nrContact, kind: interactionKind)
                    .id(AccountsState.shared.activeAccountPublicKey)
                    .background(theme.listBackground)
            case .media:
                ProfileMediaView(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case .reactions:
                ProfileReactionsView(pubkey: nrContact.pubkey)
                    .background(theme.listBackground)
            case .zaps:
                ProfileZapsView(nrContact: nrContact)
                    .background(theme.listBackground)
            case .relays:
                ProfileRelays(pubkey: nrContact.pubkey, name: nrContact.anyName)
                    .background(theme.listBackground)
            }
        } header: {
            VStack(spacing: 0) {
                ProfileSectionTabs(
                    selection: visibleSection,
                    select: { selectedSection = $0 },
                    showsArticles: vm.showArticlesTab,
                    showsHighlights: vm.showHighlightsTab,
                    showsLists: vm.showListsTab,
                    showsPersonalInteractions: showsPersonalInteractions
                )
                if visibleSection == .withYou {
                    ProfileWithYouFilter(selection: $interactionKind)
                }
            }
            .textCase(nil)
            .listRowInsets(.init())
            .listSectionSeparator(.hidden)
            .listRowSeparator(.hidden)
        }
        .listRowInsets(EdgeInsets())
        .listSectionSeparator(.hidden)
        .listRowSeparator(.hidden)
    }
}

private enum ProfileContentSection: Equatable {
    case posts, replies, media, articles, highlights, lists, reactions, zaps, relays, withYou

    // Existing profile destinations pass their initial section by name.
    init?(rawValue: String) {
        switch rawValue {
        case "Posts": self = .posts
        case "Replies": self = .replies
        case "Media": self = .media
        case "Articles": self = .articles
        case "Highlights": self = .highlights
        case "Lists": self = .lists
        case "Reactions": self = .reactions
        case "Zaps": self = .zaps
        case "Relays": self = .relays
        case "Interactions": self = .withYou
        default: return nil
        }
    }

    var isInMore: Bool {
        switch self {
        case .posts, .replies, .media: false
        default: true
        }
    }

    var title: Text {
        switch self {
        case .posts: Text("Posts", comment: "Tab title")
        case .replies: Text("Replies", comment: "Tab title")
        case .media: Text("Media", comment: "Tab title")
        case .articles: Text("Articles", comment: "Tab title")
        case .highlights: Text("Highlights", comment: "Tab title")
        case .lists: Text("Lists", comment: "Tab title")
        case .reactions: Text("Reactions", comment: "Tab title")
        case .zaps: Text("Zaps", comment: "Tab title")
        case .relays: Text("Relays")
        case .withYou: Text("With you", comment: "Profile menu heading for this person's interactions with the signed-in account")
        }
    }
}

private struct ProfileSectionTabs: View {
    @Environment(\.theme) private var theme

    let selection: ProfileContentSection
    let select: (ProfileContentSection) -> Void
    let showsArticles: Bool
    let showsHighlights: Bool
    let showsLists: Bool
    let showsPersonalInteractions: Bool

    var body: some View {
        HStack(spacing: 0) {
            tab(.posts)
            tab(.replies)
            tab(.media)

            Menu {
                if showsArticles || showsHighlights || showsLists {
                    Section {
                        if showsArticles { menuItem(.articles) }
                        if showsHighlights { menuItem(.highlights) }
                        if showsLists { menuItem(.lists) }
                    }
                }

                Section {
                    menuItem(.reactions)
                    if #available(iOS 16.0, *) {
                        menuItem(.zaps)
                    }
                }

                if showsPersonalInteractions {
                    Section {
                        menuItem(.withYou)
                    }
                }

                Section {
                    menuItem(.relays)
                }
            } label: {
                tabLabel(selected: selection.isInMore) {
                    HStack(spacing: 4) {
                        menuTabTitle
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(menuTabTitle)
            .accessibilityHint(Text("More profile sections", comment: "Accessibility hint for the profile tab that opens additional sections"))
            .accessibilityAddTraits(selection.isInMore ? .isSelected : [])
        }
        .textCase(nil)
        .background(alignment: .bottom) {
            Divider()
        }
        .background(theme.listBackground)
    }

    private func tab(_ section: ProfileContentSection) -> some View {
        Button {
            select(section)
        } label: {
            tabLabel(selected: selection == section) {
                section.title
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var menuTabTitle: Text {
        switch selection {
        case .posts, .replies, .media:
            Text("More", comment: "Profile tab that opens the menu of additional profile sections")
        default:
            selection.title
        }
    }

    private func tabLabel(selected: Bool, @ViewBuilder label: () -> some View) -> some View {
        label()
            .foregroundStyle(selected ? theme.accent : theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(selected ? theme.accent : Color.clear)
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func menuItem(_ section: ProfileContentSection) -> some View {
        Button {
            select(section)
        } label: {
            if selection == section {
                Label {
                    section.title
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                section.title
            }
        }
    }
}

private struct ProfileWithYouFilter: View {
    @Environment(\.theme) private var theme
    @Binding var selection: ProfileInteractionsView.Kind

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileInteractionsView.Kind.allCases) { kind in
                Button {
                    selection = kind
                } label: {
                    kind.shortTitle
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selection == kind ? theme.accent : theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(selection == kind ? theme.accent.opacity(0.15) : Color.clear)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.accessibilityTitle)
                .accessibilityAddTraits(selection == kind ? .isSelected : [])
            }
        }
        .background(alignment: .bottom) {
            Divider()
        }
        .background(theme.listBackground)
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

final class NXScrollPosition: ObservableObject {
    /// The latest PFP location is retained for effects that need an origin, but it
    /// deliberately does not invalidate views on every scroll frame.
    private(set) var position: CGPoint = .zero

    /// Only the toolbar observes this value. Once it is pinned at the top, further
    /// upward scrolling no longer causes view updates.
    @Published private(set) var toolbarOffset: CGFloat = 2

    func update(_ position: CGPoint) {
        self.position = position

        let newToolbarOffset = max(2, position.y)
        guard abs(newToolbarOffset - toolbarOffset) >= 0.5 else { return }
        toolbarOffset = newToolbarOffset
    }
}

struct NXScrollOffset: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
