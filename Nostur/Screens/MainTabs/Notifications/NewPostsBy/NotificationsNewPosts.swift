//
//  NotificationsNewPosts.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/11/2023.
//

import SwiftUI
import CoreData
import Combine
import NavigationBackport

struct NewPostsForPubkeys: Hashable {
    let id = UUID()
    let pubkeys: Set<String>
    let since: Int64 // for use in REQ
}

// Copy pasta from old NotificationsFollowers
struct NotificationsNewPosts: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    
    @Binding private var navPath: NBNavigationPath
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "New Posts" }
        set { setSelectedNotificationsTab(newValue) }
    }
    
    @FetchRequest
    private var notifications: FetchedResults<PersistentNotification>
    
    @State private var showNewPosts = false
    @State private var newPostsForPubkeys:NewPostsForPubkeys? = nil
    
    init(navPath: Binding<NBNavigationPath>) {
        _navPath = navPath
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "type_ == %@ AND NOT id == nil", PNType.newPosts.rawValue)
        _notifications = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        Container {
            if !notifications.isEmpty {
                ScrollView {
                    LazyVStack(spacing: GUTTER) {
                        ForEach(notifications) { notification in
                            NBNavigationLink(value: NewPostsForPubkeys(pubkeys: Set(notification.contactsInfo.map { $0.pubkey }), since: notification.since), label: {
                                Text("New posts by \(notification.contactsInfo.map { $0.name }.formatted(.list(type: .and)))")
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .overlay(alignment: .topTrailing) {
                                        Ago(notification.createdAt).layoutPriority(2)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(10)
                                    .background(theme.listBackground)
                                    .overlay(alignment: .bottom) {
                                        theme.background.frame(height: GUTTER)
                                    }
                                    
                            })
                            .id(notification.id)
                        }
                    }
                }
            }
            else {
                VStack {
                    Text("Tap the notification bell when viewing someone's profile to receive a notification when they post.")
                    HStack {
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
                        Image(systemName: "arrow.right")
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
                    }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .nbNavigationDestination(for: NewPostsForPubkeys.self, destination: { newPostsForPubkeys in
            NewPostsBy(pubkeys: newPostsForPubkeys.pubkeys, since: newPostsForPubkeys.since)
                .environment(\.theme, theme)
                .environment(\.containerID, containerID)
        })
    }
}

#Preview("Notifications New Posts") {
   PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadNewPostsNotification()
    }) {
        VStack {
            NotificationsNewPosts(navPath: .constant(NBNavigationPath()))
        }
    }
}
