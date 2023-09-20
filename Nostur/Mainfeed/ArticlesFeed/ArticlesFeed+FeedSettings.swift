//
//  ArticlesFeed+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct ArticleFeedSettings: View {
    
    @ObservedObject var vm:ArticlesFeedViewModel
    @Binding var showFeedSettings:Bool
    @State var needsReload = false
    
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
                        Text("Settings for: Articles")
                            .fontWeight(.bold)
                            .hCentered()
                            .padding(.bottom, 20)
                        
                        Text("Time frame")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Picker("Time frame", selection: $vm.ago) {
                            Text("Year").tag(356)
                            Text("Month").tag(31)
                            Text("Week").tag(7)
                            Text("Day").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        Text("The article feed shows articles from people you follow in the selected time frame")
                            .padding(.top, 20)
                    }
                }
                .padding(20)
                .ignoresSafeArea()
                .offset(y: 1.0)
            }
            .onReceive(receiveNotification(.showFeedToggles)) { _ in
                if showFeedSettings {
                    showFeedSettings = false
                }
            }
    }
}

struct ArticleFeedSettingsTester: View {
    var body: some View {
        NavigationStack {
            VStack {
                ArticleFeedSettings(vm: ArticlesFeedViewModel(), showFeedSettings: .constant(true))
                Spacer()
            }
        }
        .onAppear {
            Theme.default.loadPurple()
        }
    }
}


struct ArticleFeedSettings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            ArticleFeedSettingsTester()
        }
    }
}

