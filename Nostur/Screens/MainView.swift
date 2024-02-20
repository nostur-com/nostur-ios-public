//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI
import NavigationBackport

struct MainView: View {
    @EnvironmentObject private var themes: Themes
    @State private var fg:FollowingGuardian = .shared // If we put this on NosturApp the preview environment keeps loading it
    @State private var fn:FollowerNotifier = .shared
    @State private var newPost: NRPost? // Setting this will show shortcut to open a new just posted post in toolbar
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Following" }
    }
    
    @State private var navPath = NBNavigationPath()
    @State private var lastPathPostId: String? = nil // Need to track .id of last added to navigation stack so we can remove on undo send if needed
    @State private var account: CloudAccount? = nil
    @State private var showingNewNote = false
    @ObservedObject private var settings:SettingsStore = .shared
    @State private var showingOtherContact:NRContact? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            if let account = account {
                FollowingAndExplore(account: account, showingOtherContact: $showingOtherContact)
//                    .transaction { t in t.animation = nil }
                    .background(themes.theme.listBackground)
                    .withNavigationDestinations()
                    .overlay(alignment: .bottomTrailing) {
                        NewNoteButton(showingNewNote: $showingNewNote)
                            .padding([.top, .leading, .bottom], 10)
                            .padding([.trailing], 25)
                    }
                    .overlay(alignment: .bottom) {
                        VStack {
                            AnyStatus(filter: "APP_NOTICE")
                            #if DEBUG
                            AnyStatus(filter: "RELAY_NOTICE")
                            #endif
                            if settings.statusBubble {
                                ProcessingStatus()
                                    .opacity(0.85)
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .sheet(isPresented: $showingNewNote) {
                        NBNavigationStack {
                            if account.isNC {
                                WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                                    ComposePostCompat(onDismiss: { showingNewNote = false })
                                        .environmentObject(themes)
                                }
                            }
                            else {
                                ComposePostCompat(onDismiss: { showingNewNote = false })
                                    .environmentObject(themes)
                            }
                        }
                        .presentationBackgroundCompat(themes.theme.background)
                        .nbUseNavigationStack(.never)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 10) {
                                PFP(pubkey: account.publicKey, account: account, size: 30)
                                    .onTapGesture {
                                        SideBarModel.shared.showSidebar = true
                                    }
                                    .accessibilityLabel("Account menu")
                                
                                // Shortcut to open a new just posted post
                                if newPost != nil {
                                    Image(systemName: "ellipsis.bubble")
                                        .frame(height: 30)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            self.goToNewPost()
                                        }
                                }
                            }
                        }
                        
                        ToolbarItem(placement: .principal) {
                            if let showingOtherContact = showingOtherContact {
                                HStack(spacing: 6) {
                                    PFP(pubkey: showingOtherContact.pubkey, nrContact: showingOtherContact, size: 30)
                                        .frame(height:30)
                                        .clipShape(Circle())
                                        .onTapGesture {
                                            sendNotification(.shouldScrollToTop)
                                        }
                                    
                                    Image(systemName: "multiply.circle.fill")
                                        .frame(height:30)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard let account = Nostur.account() else { return }
                                            self.showingOtherContact = nil
                                            LVMManager.shared.followingLVM(forAccount: account)
                                                .revertBackToOwnFeed()
                                        }
                                }
                            }
                            else {
                                Image("NosturLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height:30)
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        sendNotification(.shouldScrollToTop)
                                    }
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Image(systemName: "tortoise")
                                .foregroundColor(themes.theme.accent.opacity(settings.lowDataMode ? 1.0 : 0.3))
                                .onTapGesture {
                                    settings.lowDataMode.toggle()
                                    sendNotification(.anyStatus, ("Low Data mode: \(settings.lowDataMode ? "enabled" : "disabled")", "APP_NOTICE"))
                                }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Image(systemName: "gearshape")
                                .foregroundColor(themes.theme.accent)
                                .onTapGesture {
                                    sendNotification(.showFeedToggles)
                                }
                        }
                    }
            }
        }
        .onReceive(receiveNotification(.showingSomeoneElsesFeed)) { notification in
            let nrContact = notification.object as! NRContact
            showingOtherContact = nrContact
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! CloudAccount
            guard self.account != account else { return }
            self.account = account
            if selectedSubTab != "Following" {
                UserDefaults.standard.setValue("Following", forKey: "selected_subtab")
            }
        }
        .onAppear {
            self.account = Nostur.account()
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD || horizontalSizeClass == .compact else { return }
            guard selectedTab == "Main" else { return }
            navPath.append(destination.destination)
            
            // We need to know which .id is last added the stack (for undo), but we can't get from .navPath (private / internal)
            // So we track it separately in .lastPathPostId
            if (type(of: destination.destination) == NRPost.self) {
                let lastPath = destination.destination as! NRPost
                lastPathPostId = lastPath.id
            }
        }
        .onReceive(receiveNotification(.navigateToOnMain)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
            
            
            // We need to know which .id is last added the stack (for undo), but we can't get from .navPath (private / internal)
            // So we track it separately in .lastPathPostId
            if (type(of: destination.destination) == NRPost.self) {
                let lastPath = destination.destination as! NRPost
                lastPathPostId = lastPath.id
            }
        }
        .onReceive(receiveNotification(.didTapTab)) { notification in
            guard let tabName = notification.object as? String, tabName == "Main" else { return }
            if navPath.count == 0 {
                sendNotification(.shouldScrollToFirstUnread)
            }
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            // No need to clear if we are already at root
            guard navPath.count > 0 else { return }
            lastPathPostId = nil
            
            // if notification.object is not empty/nil
            if let tab = notification.object as? String, tab == "Main" {
                navPath.removeLast(navPath.count)
            }
            else if notification.object == nil {
                // if empty/nil, we always clear
                navPath.removeLast(navPath.count)
            }
        }
        .onReceive(receiveNotification(.newPostSaved)) { notification in
            
            // When a new post is made by our account, we show a quick shortcut in toolbar to open that post

            guard let account = account else { return }
            let accountPubkey = account.publicKey
            let event = notification.object as! Event
            bg().perform {
                guard event.pubkey == accountPubkey else { return }
                EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "MainView.newPostSaved")
                
                let newPost = NRPost(event: event, withParents: true, withReplies: true, withRepliesCount: true, cancellationId: event.cancellationId)

                DispatchQueue.main.async {
                    self.newPost = newPost // Setting this will activate the shortcut
                }
            }
        }
        .onReceive(receiveNotification(.unpublishedNRPost)) { notification in
            
            // When we 'Undo send' a new post, we need to remove it from the stack
            
            let nrPost = notification.object as! NRPost
            if nrPost.id == newPost?.id {
                newPost = nil // Also remove the shortcut from toolbar
                
                // Pop last from stack if the lastPathPostId is the undo post
                guard let lastPathPostId, lastPathPostId == nrPost.id else { return }
                navPath.pop()
            }
        }
    }
    
    func goToNewPost() {
        guard let newPost else { return }
        navigateTo(newPost)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadFollowers()
        }) {
            MainView()
        }
    }
}
