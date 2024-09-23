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
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    
    @Binding private var navPath: NBNavigationPath
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Notifications" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "New Posts" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @FetchRequest
    private var notifications: FetchedResults<PersistentNotification>
    
    @State private var showNewPosts = false
    @State private var newPostsForPubkeys:NewPostsForPubkeys? = nil
    
    init(pubkey: String, navPath: Binding<NBNavigationPath>) {
        _navPath = navPath
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND type_ == %@ AND NOT id == nil", pubkey, PNType.newPosts.rawValue)
        _notifications = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
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
                                    .background(themes.theme.background)
                            })
                            .id(notification.id)
                        }
                    }
                }
                .onReceive(receiveNotification(.didTapTab)) { notification in
                    guard selectedNotificationsTab == "New Posts" else { return }
                    guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                    if navPath.count == 0, let topId = notifications.first?.id {
                        withAnimation {
                            proxy.scrollTo(topId)
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
                                    .background(themes.theme.listBackground)
                                    .border(themes.theme.listBackground, width: 2.0)
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
                                    .background(themes.theme.listBackground)
                                    .offset(y: -3)
                            }
                            .offset(y: 3)
                    }
                }
                .centered()
            }
        }
        .background(themes.theme.listBackground)
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! CloudAccount
            notifications.nsPredicate = NSPredicate(format: "pubkey == %@ AND type_ == %@ AND NOT id == nil", account.publicKey, PNType.newPosts.rawValue)
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
        .nbNavigationDestination(for: NewPostsForPubkeys.self, destination: { newPostsForPubkeys in
            NewPostsBy(pubkeys: newPostsForPubkeys.pubkeys, since: newPostsForPubkeys.since)
                .environmentObject(themes)
                .environmentObject(dim)
        })
    }
}

#Preview("Notifications New Posts") {
    let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadNewPostsNotification()
    }) {
        VStack {
            NotificationsNewPosts(pubkey: pubkey, navPath: .constant(NBNavigationPath()))
        }
    }
}
