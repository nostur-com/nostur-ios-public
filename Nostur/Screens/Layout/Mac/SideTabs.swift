//
//  SideTabs.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2025.
//

import SwiftUI

struct SideTabs: View {
    @EnvironmentObject private var dm: DirectMessageViewModel
    @Environment(\.showSidebar) @Binding var showSidebar: Bool
    @Environment(\.theme) private var theme
    @ObservedObject var vm: MacColumnsVM
    @Binding var selectedTab: String
    @State private var unread: Int = 0
    
    var body: some View {
        VStack(alignment: .center) {
            if let account = account() {
                PFP(pubkey: account.publicKey, account: account, size: 30)
                    .padding(10)
                    .onTapGesture {
                        showSidebar = true
                    }
            }
            
            Group {
                
                Button("Following", systemImage: "house") {
                    selectedTab = "Main"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Main" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Notifications", systemImage: "bell") {
                    selectedTab = "Notifications"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Notifications" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .badgeCompat(unread)
                
                Button("Search", systemImage: "magnifyingglass") {
                    selectedTab = "Search"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Search" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Bookmarks", systemImage: "bookmark") {
                    selectedTab = "Bookmarks"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Bookmarks" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Messages", systemImage: "envelope") {
                    selectedTab = "Messages"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Messages" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                .badgeCompat((dm.unread + dm.newRequests))
            
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundColor(theme.accent)
            
            Spacer()
            
            
            Group {
                Button { vm.addColumn() } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .help("Add column")
                .disabled(!vm.allowAddColumn)
                Color.clear.frame(height: 5)
                Button { vm.removeColumn() } label: {
                    Image(systemName: "rectangle.stack.badge.minus")
                }
                .help("Remove column")
                .disabled(!vm.allowRemoveColumn)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundColor(theme.accent)
            
            Spacer()
            
            Button { sendNotification(.newPost) } label: {
                Image(systemName: "square.and.pencil.circle.fill")
            }
            .help("New Post")
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 24))
            .foregroundColor(theme.accent)
            .padding(.bottom, 20)
        }
//        .padding(.top, 100)
        
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
            if unread != self.unread {
                self.unread = unread
            }
        }
    }
}
