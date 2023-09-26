//
//  NotificationSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/09/2023.
//

import SwiftUI

struct NotificationSettings: View {

    @Binding var showFeedSettings:Bool
    @AppStorage("notifications_mute_follows") var muteFollows:Bool = false
    @AppStorage("notifications_mute_reactions") var muteReactions:Bool = false
    @AppStorage("notifications_mute_zaps") var muteZaps:Bool = false
    @AppStorage("notifications_mute_reposts") var muteReposts:Bool = false
    
    var body: some View {
        Rectangle().fill(.thinMaterial)
            .ignoresSafeArea()
            .onTapGesture {
                showFeedSettings = false
            }
            .overlay(alignment: .top) {
                Box {
                    VStack(alignment: .leading) {
                        AppThemeSwitcher(showFeedSettings: $showFeedSettings)
                        .padding(.bottom, 15)
                        Text("Notification settings")
                            .fontWeight(.bold)
                            .hCentered()
                        
                        Toggle(isOn: $muteFollows) {
                            Text("Mute new follower notifications")
                        }
                        
                        Toggle(isOn: $muteReposts) {
                            Text("Mute repost notifications")
                        }
                        
                        Toggle(isOn: $muteReactions) {
                            Text("Mute reaction notifications")
                        }
                        
                        Toggle(isOn: $muteZaps) {
                            Text("Mute zap notifications")
                        }
                    }
                }
                .padding(20)
                .ignoresSafeArea()
                .offset(y: 1.0)
            }
    }
}

struct NotificationSettingsTester: View {
    var body: some View {
        NavigationStack {
            VStack {
                NotificationSettings(showFeedSettings: .constant(true))
                Spacer()
            }
        }
        .onAppear {
            Theme.default.loadPurple()
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
