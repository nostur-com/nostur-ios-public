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
    @Binding var columnsCount: Int
    @Binding var selectedTab: String
    @State private var unread: Int = 0
    
    var body: some View {
        VStack(alignment: .center) {
            if let account = account() {
                PFP(pubkey: account.publicKey, account: account, size:30)
                    .padding(10)
                    .onTapGesture {
                        showSidebar = true
                    }
            }
            
            Group {
                
                Button("Following", systemImage: "house.fill") {
                    selectedTab = "Main"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Main" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Notifications", systemImage: "bell.fill") {
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
                
                Button("Bookmarks", systemImage: "bookmark.fill") {
                    selectedTab = "Bookmarks"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Bookmarks" ? theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Messages", systemImage: "envelope.fill") {
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
                Button { addColumn() } label: {
                    Image(systemName: "rectangle.stack.fill.badge.plus")
                }
                Color.clear.frame(height: 5)
                Button { removeColumn() } label: {
                    Image(systemName: "rectangle.stack.badge.minus")
                }
            }
            Spacer()
        }
//        .padding(.top, 100)
        
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
            if unread != self.unread {
                self.unread = unread
            }
        }
    }
    
    func addColumn() {
        guard columnsCount < 10 else { return }
        columnsCount += 1
    }
    
    func removeColumn() {
        guard columnsCount > 1 else { return }
        columnsCount -= 1
    }
}
