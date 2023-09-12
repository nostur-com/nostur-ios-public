//
//  Search.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//

import SwiftUI
import Combine
import NostrEssentials

@MainActor
struct Search: View {
    @EnvironmentObject var theme:Theme
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
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
//    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
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
                            .background(theme.background)
                    }
                    ForEach(nrPosts.prefix(75)) { nrPost in
                        Box(nrPost: nrPost) {
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                        }
                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
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
            .background(theme.listBackground)
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
                case .other(let term):
                    otherSearch(term)
                }
            }
            .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
                let importedSubIds = notification.object as! ImportedNotification

                let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)

                reqTasks.forEach { task in
                    task.process()
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
