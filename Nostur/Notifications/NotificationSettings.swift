//
//  NotificationSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/09/2023.
//

import SwiftUI
import BackgroundTasks

struct NotificationSettings: View {
    @ObservedObject private var ss:SettingsStore = .shared
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notifications_mute_follows") var muteFollows:Bool = false
    @AppStorage("notifications_mute_reactions") var muteReactions:Bool = false
    @AppStorage("notifications_mute_zaps") var muteZaps:Bool = false
    @AppStorage("notifications_mute_reposts") var muteReposts:Bool = false
    @AppStorage("notifications_mute_new_posts") var muteNewPosts:Bool = false
    
    var body: some View {
        Form {
            Section("App theme") {
                AppThemeSwitcher()
            }
            
            Section("Show unread count badge") {
                Toggle(isOn: $muteFollows.not) {
                    Text("New followers")
                }
                
                Toggle(isOn: $muteReposts.not) {
                    Text("New reposts")
                }
                
                Toggle(isOn: $muteReactions.not) {
                    Text("New reactions")
                }
                
                Toggle(isOn: $muteZaps.not) {
                    Text("New zaps")
                }
                
                Toggle(isOn: $muteNewPosts.not) {
                    Text("New posts")
                    Text("Only for people where you have activated the notification bell")
                }
            }
           
            Section {
                Toggle(isOn: $ss.receiveLocalNotifications) {
                    Text("Mentions, replies, or DMs")
                    Text("Receive notifications when Nostur is in background")
                }
                .onChange(of: ss.receiveLocalNotifications) { receiveLocalNotifications in
                    if receiveLocalNotifications {
                        requestNotificationPermission(redirectToSettings: true)
                    }
                    else {
                        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.nostur.app-refresh")
                    }
                }
                
                if ss.receiveLocalNotifications {
                    Toggle(isOn: $ss.receiveLocalNotificationsLimitToFollows) {
                        Text("Only from follows")
                        Text("Limit Home/Lock screen notifications to only from people you follow")
                    }
                }
            } header: { Text("Home/Lock screen notifications") } footer: { Text("Home/Lock screen notifications are only active for the currently logged in account and can be a bit delayed") }
        }
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import NavigationBackport

struct NotificationSettingsTester: View {
    var body: some View {
        NBNavigationStack {
            NotificationSettings()
        }
        .onAppear {
            Themes.default.loadPurple()
        }
    }
}


struct NotificationSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NotificationSettingsTester()
        }
    }
}
