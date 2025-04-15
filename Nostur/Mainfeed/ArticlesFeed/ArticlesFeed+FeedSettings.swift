//
//  ArticlesFeed+FeedSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI

struct ArticleFeedSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: ArticlesFeedViewModel
    @State var needsReload = false
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    
    var body: some View {
        Form {
            if #available(iOS 16, *) {
                Section("App theme") {
                    AppThemeSwitcher()
                }
            }
            Section {
                Picker("Time frame", selection: $vm.ago) {
                    Text("Year").tag(356)
                    Text("Month").tag(31)
                    Text("Week").tag(7)
                    Text("Day").tag(1)
                }
                .pickerStyle(.segmented)
            } header: { Text("Article feed time frame") } footer: { Text("The article feed shows articles from people you follow in the selected time frame") }
            
            Toggle(isOn: $enableArticleFeed, label: {
                Text("Show feed in tab bar")
            })
        }
        .navigationTitle("Article feed settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import NavigationBackport

struct ArticleFeedSettingsTester: View {
    var body: some View {
        NBNavigationStack {
            ArticleFeedSettings(vm: ArticlesFeedViewModel())
                .environmentObject(Themes.default)
        }
        .onAppear {
            Themes.default.loadPurple()
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

