//
//  DMs.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/09/2023.
//

import SwiftUI
import Combine
import NavigationBackport

struct DMs: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    
    @State private var tab = "Accepted"
    
    public let pubkey: String
    @EnvironmentObject private var vm: DirectMessageViewModel
    
    @State private var showingNewDM = false
    @State private var showDMToggles = false
    @State private var preloadNewDMInfo: (String, NRContact)? = nil // pubkey and Contact
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        
        VStack {
            HStack {
                Button {
                    withAnimation {
                        tab = "Accepted"
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Accepted", comment: "Tab title for accepted DMs (Direct Messages)").lineLimit(1)
                                .font(.subheadline)
                                .foregroundColor(theme.accent)
                            //                                    .frame(maxWidth: .infinity)
                            //                                    .padding(.top, 8)
                            //                                    .padding(.bottom, 5)
                            if vm.unread > 0 {
                                Menu {
                                    Button {
                                        vm.markAcceptedAsRead()
                                    } label: {
                                        Label(String(localized: "Mark all as read", comment:"Menu action to mark all messages as read"), systemImage: "envelope.open")
                                    }
                                } label: {
                                    Text("\(vm.unread)")
                                        .font(.footnote)
                                        .foregroundColor(.white)
                                        .padding(.horizontal,6)
                                        .background(Capsule().foregroundColor(.red))
                                        .offset(x:-4, y: 0)
                                }
                            }
                        }
                        .padding(.horizontal, 5)
                        .frame(height: 41)
                        .fixedSize()
                        theme.accent
                            .frame(height: 3)
                            .opacity(tab == "Accepted" ? 1 : 0.15)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                
                Button {
                    withAnimation {
                        tab = "Requests"
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Requests", comment: "Tab title for DM (Direct Message) requests").lineLimit(1)
                                .font(.subheadline)
                                .foregroundColor(theme.accent)
                            //                                    .frame(maxWidth: .infinity)
                            //                                    .padding(.top, 8)
                            //                                    .padding(.bottom, 5)
                            if vm.newRequests > 0 {
                                Menu {
                                    Button {
                                        vm.markRequestsAsRead()
                                    } label: {
                                        Label(String(localized: "Mark all as read", comment:"Menu action to mark all dm requests as read"), systemImage: "envelope.open")
                                    }
                                } label: {
                                    Text("\(vm.newRequests)")
                                        .font(.footnote)
                                        .foregroundColor(.white)
                                        .padding(.horizontal,6)
                                        .background(Capsule().foregroundColor(.red))
                                        .offset(x:-4, y: 0)
                                }
                            }
                        }
                        .padding(.horizontal, 5)
                        .frame(height: 41)
                        .fixedSize()
                        theme.accent
                            .frame(height: 3)
                            .opacity(tab == "Requests" ? 1 : 0.15)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            if vm.scanningMonthsAgo != 0 {
                Text("Scanning relays for messages \(vm.scanningMonthsAgo)/36 months ago...")
                    .italic()
                    .hCentered()
            }
            switch (tab) {
            case "Accepted":
                if !vm.conversationRows.isEmpty {
                    DirectMessageRows(pubkey: pubkey, conversationRows: $vm.conversationRows)
                }
                else {
                    Text("You have not received any messages", comment: "Shown on the DM view when there aren't any direct messages to show")
                        .centered()
                }
            case "Requests":
                if !vm.requestRows.isEmpty || vm.showNotWoT {
                    DirectMessageRows(pubkey: pubkey, conversationRows: $vm.requestRows)
                }
                else {
                    Text("No message requests", comment: "Shown on the DM requests view when there aren't any message requests to show")
                        .centered()
                }
            default:
                EmptyView()
            }
            Spacer()
            Text("Note: The contents of DMs is encrypted but the metadata is not. Who you send a message to and when is public.", comment:"Informational message on the DM screen")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.horizontal, 20)
                .padding(.trailing, 80)
                .padding(.bottom, 5)
        }
        .overlay(alignment: .bottomTrailing) {
            NewDMButton(showingNewDM: $showingNewDM)
        }
        .nbNavigationDestination(for: Conversation.self) { conv in
            if let event = conv.mostRecentEvent.toMain() {
                DMConversationView(recentDM: event, pubkey: self.pubkey, conv: conv)
                    .onAppear {
                        DirectMessageViewModel.default.objectWillChange.send()
                        conv.unread = 0
                        conv.dmState.markedReadAt_ = Date.now
                        conv.dmState.didUpdate.send()
                    }
                    .environment(\.theme, theme)
                    .environment(\.containerID, containerID)
            }
        }
        .sheet(isPresented: $showingNewDM) {
            NBNavigationStack {
                NewDM(showingNewDM: $showingNewDM, tab: $tab)
                    .nosturNavBgCompat(theme: theme)
                    .onAppear {
                        if let preloadNewDMInfo {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                sendNotification(.preloadNewDMInfo, preloadNewDMInfo)
                            }
                        }
                    }
                    .environment(\.theme, theme)
                    .environmentObject(la)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .onReceive(receiveNotification(.triggerDM)) { notification in
            let preloadNewDMInfo = notification.object as! (String, NRContact)
            self.preloadNewDMInfo = preloadNewDMInfo
            showingNewDM = true
        }
        .navigationTitle(String(localized: "Messages", comment: "Navigation title for DMs (Direct Messages)"))
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "gearshape")
                    .foregroundColor(theme.accent)
                    .onTapGesture {
                        sendNotification(.showDMToggles)
                    }
                    .help("Settings...")
            }
        }
        .overlay(alignment: .top) {
            if showDMToggles {
                DMSettings(showDMToggles: $showDMToggles, tab: $tab)
            }
        }
        .onReceive(receiveNotification(.showDMToggles)) { _ in
            showDMToggles = true
        }
        .onAppear {
            // do 2 month scan if we have no messages (probably first time)
            // longer 36 month scan is in settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if (DirectMessageViewModel.default.conversationRows.count == 0 && DirectMessageViewModel.default.requestRows.count == 0) {
                    DirectMessageViewModel.default.rescanForMissingDMs(2)
                }
            }
        }
        .background(theme.listBackground)
        .nosturNavBgCompat(theme: theme) // <-- Needs to be inside navigation stack
        .tabBarSpaceCompat()
    }
}


struct DMNavigationStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let content: Content
    @State private var navPath = NBNavigationPath()
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Messages" }
        set { setSelectedTab(newValue) }
    }
    
    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        NBNavigationStack(path: $navPath) {
            content
                .environment(\.containerID, "Messages")
                .onReceive(receiveNotification(.navigateTo)) { notification in
                    let destination = notification.object as! NavigationDestination
                    guard !IS_IPAD || horizontalSizeClass == .compact else { return }
                    guard destination.context == "Messages" else { return }
                    navPath.append(destination.destination)
                }
                .onReceive(receiveNotification(.clearNavigation)) { notification in
                    navPath.removeLast(navPath.count)
                }
        }
        .nbUseNavigationStack(.never)
    }
}

struct DirectMessagesX_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadAccount()
            pe.loadDMs()
            pe.loadDMs2()
            DirectMessageViewModel.default.load()
        }) {
            DMNavigationStack {
                DMContainer()
                    .environmentObject(DirectMessageViewModel.default)
            }
        }
    }
}

struct DMContainer: View {
    @EnvironmentObject var la: LoggedInAccount
    
    var body: some View {
        VStack(spacing: 0) {
            if la.account.isNC {
                Text("Direct Messages using a nsecBunker login are not available yet")
                    .centered()
            }
            else {
                DMs(pubkey: la.account.publicKey)
                    .environmentObject(VideoPostPlaybackCoordinator())
            }
            
            AudioOnlyBarSpace()
        }
    }
}
