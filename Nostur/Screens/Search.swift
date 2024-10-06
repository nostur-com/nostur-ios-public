//
//  Search.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//

import SwiftUI
import Combine
import NostrEssentials
import NavigationBackport

@MainActor
struct Search: View {
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @State var nrPosts: [NRPost] = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts: FetchedResults<Contact>
    
    private var filteredContactSearchResults: [Contact] {
        let wot = WebOfTrust.shared
        if WOT_FILTER_ENABLED() {
            return contacts
                // WoT enabled, so put in-WoT before non-WoT
                .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                // Put following before non-following
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
        else {
            // WoT disabled, just following before non-following
            return contacts
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
    }

    @State var searching = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Search" }
    }
    
    
    @State private var navPath = NBNavigationPath()

    @State private var searchText = ""
    @State var searchTask: Task<Void, Never>? = nil
    @State var backlog = Backlog()
    @ObservedObject var settings: SettingsStore = .shared
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isSearchingHashtag: Bool {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isHashtag(term)
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            VStack {
                Box { // @FocusState doesn't work when TextField is in ToolBarItem sigh...
                    SearchBox(prompt: String(localized: "Search...", comment: "Placeholder text in a search input box"), text: $searchText)
                        .padding(10)
                }
                AvailableWidthContainer {
                    ScrollView {
                        if isSearchingHashtag {
                            FollowHashtagTile(hashtag:String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(1)), account:la.account)
                                .padding([.top, .horizontal], 10)
                        }
                        if (filteredContactSearchResults.isEmpty && nrPosts.isEmpty && searching) {
                            CenteredProgressView()
                        }
                        LazyVStack(spacing: GUTTER) {
                            ForEach(filteredContactSearchResults.prefix(75)) { contact in
                                ProfileRow(contact: contact)
                                    .background(themes.theme.background)
                            }
                            ForEach(nrPosts.prefix(75)) { nrPost in
                                Box(nrPost: nrPost) {
                                    if nrPost.kind == 443 {
                                        VStack {
                                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                            HStack(spacing: 0) {
                                                self.replyButton
                                                    .foregroundColor(themes.theme.footerButtons)
                                                    .padding(.leading, 10)
                                                    .padding(.vertical, 5)
                                                    .contentShape(Rectangle())
                                                    .onTapGesture {
                                                        navigateTo(nrPost)
                                                    }
                                                Spacer()
                                            }
                                        }
                                    }
                                    else {
                                        PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                    }
                                }
                                .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                            }
                        }
                        .padding(.top, 10)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    sendNotification(.showSideBar)
                                } label: {
                                    PFP(pubkey: la.account.publicKey, account: la.account, size:30)
                                }
                                .accessibilityLabel("Account menu")

                            }
        //                    ToolbarItem(placement: .principal) {
        //
        //                    }
                        }
                        .toolbarNavigationBackgroundVisible()
                    }
                    .scrollDismissesKeyboardCompat()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if settings.statusBubble {
                    ProcessingStatus()
                        .opacity(0.85)
                        .padding(.bottom, 10)
                }
            }
            .background(themes.theme.listBackground)
            .nosturNavBgCompat(themes: themes)
            .withNavigationDestinations()
            .navigationTitle(String(localized:"Search", comment: "Navigation title for Search screen"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { searchInput in
                nrPosts = []
                contacts.nsPredicate = NSPredicate(value: false)
                navPath.removeLast(navPath.count)
                switch typeOfSearch(searchInput) {
                case .nprofile1(let term):
                    nprofileSearch(term)
                case .naddr1(let term):
                    naddrSearch(term)
                case .nevent1(let term):
                    neventSearch(term)
                case .npub1(let term):
                    npubSearch(term)
                case .nametag(let term):
                    nametagSearch(term)
                case .hashtag(let term):
                    hashtagSearch(term)
                case .note1(let term):
                    note1Search(term)
                case .hexId(let term):
                    hexIdSearch(term)
                case .nip05(let nip05parts):
                    nip05Search(nip05parts)
                case .url(let term):
                    urlSearch(term)
                case .other(let term):
                    otherSearch(term)
                }
            }
            .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
                bg().perform {
                    guard let backlog else { return }
                    let reqTasks = backlog.tasks(with: subscriptionIds)
                    reqTasks.forEach { task in
                        task.process()
                    }
                }
            }
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard type(of: destination.destination) == Nevent1Path.self || type(of: destination.destination) == Nprofile1Path.self || type(of: destination.destination) == HashtagPath.self || horizontalSizeClass == .compact else { return }
 
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
//                    navPath.removeLast(navPath.count)
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
        .nbUseNavigationStack(.never)
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Comments")
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

import NavigationBackport

struct Search_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
            pe.loadContacts()
        }) {
            NBNavigationStack {
                if let lia = NRState.shared.loggedInAccount {
                    Search()
                        .environmentObject(lia)
                }
            }
        }
    }
}
