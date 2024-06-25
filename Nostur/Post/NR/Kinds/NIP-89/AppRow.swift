//
//  AppRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/01/2024.
//

import SwiftUI
import NukeUI
import NavigationBackport

struct AppRow: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.openURL) private var openURL
    public var app: SuggestedApp
    private var appName: String { app.name }
    private var appDescription: String? { app.description }
    private var appLogoUrl: URL? { app.logoUrl }
    private var appOpenURL: URL { app.openUrl }
    
    public var theme: Theme
    @ObservedObject private var ss: SettingsStore = .shared
    @State private var showDetailSheet = false
    
    var body: some View {
        HStack(alignment: .center) {
            if !ss.lowDataMode, let appLogoUrl {
                LazyImage(url: appLogoUrl) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    else if state.isLoading { 
                        CenteredProgressView()
                    }
                    else {
                        Color(.secondarySystemBackground)
                    }
                }
                .pipeline(ImageProcessing.shared.content)
                .frame(width: 50, height: 50)
                .roundedCorner(8, corners: .allCorners)
            }

            VStack(alignment: .leading) {
                Text(appName)
                    .lineLimit(1)
                    .fontWeightBold()
                if let appDescription {
                    Text(appDescription)
                        .lineLimit(1)
                        .font(.subheadline)
                        .foregroundColor(theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Image(systemName: "chevron.right")
//                .resizable()
                .font(.title)
                .foregroundColor(theme.secondary)
                
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showDetailSheet = true
        }
        .sheet(isPresented: $showDetailSheet, content: {
            NBNavigationStack {
                VStack(spacing: 10) {
                    Spacer()
                    AppDetail(app: app, theme: theme, onDismiss: {
                        showDetailSheet = false
                    })
                    .padding()
                    .environmentObject(themes)
                }
            }
            .nbUseNavigationStack(.never)
            .presentationDetents350l()
        })
    }
    
    private func openApp() {
        openURL(appOpenURL)
    }
}

#Preview {
    NBNavigationStack {
        AppRow(app: SuggestedApp(id: "1", name: "Nostur", description: "A nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\nA nostr client\n", logoUrl: URL(string: "https://nostur.com/nostur.png")!, openUrl: URL(string: "https://nostur.com")!, recommendedBy: [
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            ),
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            ),
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            ),
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            ),
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            ),
            (
                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
            )
        ]), theme: Themes.default.theme)
            .padding(10)
    }
}
