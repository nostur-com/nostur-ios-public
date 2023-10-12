//
//  DMs.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/09/2023.
//

import SwiftUI
import Combine

struct DMs: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes:Themes
    @State var navPath = NavigationPath()
    @AppStorage("selected_tab") var selectedTab = "Messages"
    @State var tab = "Accepted"
    
    let pubkey:String
    @EnvironmentObject var vm:DirectMessageViewModel
    
    
    @State var showingNewDM = false
    @State var showDMToggles = false
    
    var body: some View {
        NavigationStack(path: $navPath) {
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
                            Rectangle()
                                .frame(height: 3)
                                .background(themes.theme.accent)
                                .opacity(tab == "Accepted" ? 1 : 0.15)
                        }
                    }
                    
                    Button {
                        withAnimation {
                            tab = "Requests"
                        }
                    } label: {
                        VStack(spacing:0) {
                            HStack {
                                Text("Requests", comment: "Tab title for DM (Direct Message) requests").lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 8)
                                    .padding(.bottom, 5)
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
                            Rectangle()
                                .frame(height: 3)
                                .background(themes.theme.accent)
                                .opacity(tab == "Requests" ? 1 : 0.15)
                        }
                    }
                }
                if vm.scanningMonthsAgo != 0 {
                    Text("Scanning relays for messages \(vm.scanningMonthsAgo)/12 months ago...")
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
                        VStack {
                            DirectMessageRows(pubkey: pubkey, conversationRows: $vm.requestRows)
                        }
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
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
            }
            .overlay(alignment: .bottomTrailing) {
                NewDMButton(showingNewDM: $showingNewDM)
                    .padding([.top, .leading, .bottom], 10)
                    .padding([.trailing], 25)
            }
            .navigationDestination(for: Conversation.self) { conv in
                if let event = conv.mostRecentEvent.toMain() {
                    DMConversationView(recentDM: event, pubkey: self.pubkey, conv: conv)
                        .onAppear {
                            DirectMessageViewModel.default.objectWillChange.send()
                            conv.unread = 0
                            bg().perform {
                                conv.dmState.markedReadAt = Date.now
                                conv.dmState.didUpdate.send()
                            }
                        }
                }
            }
            .sheet(isPresented: $showingNewDM) {
                NavigationStack {
                    NewDM(showingNewDM: $showingNewDM, tab: $tab)
                }
                .presentationBackground(themes.theme.background)
            }
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard !IS_IPAD || horizontalSizeClass == .compact else { return }
                guard selectedTab == "Messages" else { return }
                navPath.append(destination.destination)
            }
            .onReceive(receiveNotification(.clearNavigation)) { notification in
                navPath.removeLast(navPath.count)
            }
            
            .navigationTitle(String(localized: "Messages", comment: "Navigation title for DMs (Direct Messages)"))
            .navigationBarTitleDisplayMode(.inline)
            
            .background(themes.theme.listBackground)
            
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "gearshape")
                        .foregroundColor(themes.theme.accent)
                        .onTapGesture {
                            sendNotification(.showDMToggles)
                        }
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
                // longer 12 month scan is in settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if (DirectMessageViewModel.default.conversationRows.count == 0 && DirectMessageViewModel.default.requestRows.count == 0) {
                        DirectMessageViewModel.default.rescanForMissingDMs(2)
                    }
                }
            }
        }
    }
}

struct DirectMessagesX_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadDMs()
            pe.loadDMs2()
        }) {
            DMContainer()
                .environmentObject(DirectMessageViewModel.default)
        }
    }
}

struct DMContainer: View {
    @EnvironmentObject var la:LoggedInAccount
    
    var body: some View {
        if la.account.isNC {
            Text("Direct Messages using a nsecBunker login are not available yet")
                .centered()
        }
        else {
            DMs(pubkey: la.account.publicKey)
        }
    }
}
