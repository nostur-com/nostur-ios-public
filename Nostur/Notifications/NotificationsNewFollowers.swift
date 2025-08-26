//
//  NotificationsNewFollowers.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2023.
//

import SwiftUI
import CoreData
import Combine
import NavigationBackport

// Copy pasta from old NotificationsPosts, only using the new follower parts.
struct NotificationsFollowers: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var fl = FastLoader()
    @State private var backlog = Backlog(backlogDebugName: "NotificationsFollowers")
    @State private var didLoad = false
    @Binding private var navPath: NBNavigationPath
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Followers" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @FetchRequest
    private var notifications:FetchedResults<PersistentNotification>
    
    init(pubkey: String, navPath: Binding<NBNavigationPath>) {
        _navPath = navPath
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND type_ == %@ AND NOT id == nil", pubkey, PNType.newFollowers.rawValue)
        _notifications = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ZStack {
                theme.listBackground // List background, not toolbar / screen
                ScrollView {
                    LazyVStack(spacing: GUTTER) {
                        ForEach(notifications) { notification in
                            NewFollowersNotificationView(notification: notification)
                                .padding(10)
                                .background(theme.listBackground)
                                .overlay(alignment: .bottom) {
                                    theme.background.frame(height: GUTTER)
                                }
                                .id(notification.id)
                        }
                    }
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedNotificationsTab == "Followers" else { return }
                guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                if navPath.count == 0, let topId = notifications.first?.id {
                    withAnimation {
                        proxy.scrollTo(topId)
                    }
                }
            }
        }
        .background(theme.listBackground) // Screen / toolbar background
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            let account = notification.object as! CloudAccount
            notifications.nsPredicate = NSPredicate(format: "pubkey == %@ AND type_ == %@ AND NOT id == nil", account.publicKey, PNType.newFollowers.rawValue)
        }
    }
    
    private func saveLastSeenFollowersCreatedAt() {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Followers" else { return }
        if let first = notifications.first {
            let firstCreatedAt = first.createdAt
            bg().perform {
                if let account = account() {
                    if account.lastFollowerCreatedAt < Int64(firstCreatedAt.timeIntervalSince1970) {
                        account.lastFollowerCreatedAt = Int64(firstCreatedAt.timeIntervalSince1970)
                    }
                }
                DataProvider.shared().bgSave()
            }
        }
    }

}

#Preview("Notifications Followers") {
    let pubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadNewFollowersNotification()
    }) {
        VStack {
            NotificationsFollowers(pubkey: pubkey, navPath: .constant(NBNavigationPath()))
        }
    }
}
