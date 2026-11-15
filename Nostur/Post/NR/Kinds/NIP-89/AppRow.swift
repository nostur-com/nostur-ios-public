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
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    public var app: SuggestedApp
    private var appName: String { app.name }
    private var appDescription: String? { app.description }
    private var appLogoUrl: URL? { app.logoUrl }
    
    @ObservedObject private var ss: SettingsStore = .shared
    @State private var showDetailSheet = false
    @State private var pendingAction: AppDetail.Action?
    
    var body: some View {
        HStack(alignment: .center) {
            Group {
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
                            appIconPlaceholder
                        }
                    }
                    .pipeline(ImageProcessing.shared.content)
                }
                else {
                    appIconPlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

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
        .sheet(isPresented: $showDetailSheet, onDismiss: performPendingAction) {
            appDetailSheet
        }
    }

    @ViewBuilder
    private var appDetailSheet: some View {
        let content = NBNavigationStack {
            AppDetail(app: app) { action in
                pendingAction = action
                showDetailSheet = false
            }
            .padding()
            .environment(\.theme, theme)
        }
        .nbUseNavigationStack(.never)

        if #available(iOS 16.4, *) {
            // On Mac, a single detent keeps mouse scrolling focused on the list.
            let detents: Set<PresentationDetent> = ProcessInfo.processInfo.isMacCatalystApp
                || ProcessInfo.processInfo.isiOSAppOnMac ? [.large] : [.height(350), .large]
            content
                .presentationDetents(detents)
                .presentationContentInteraction(.scrolls)
        } else if #available(iOS 16, *) {
            content.presentationDetents([.height(350), .large])
        } else {
            content
        }
    }

    private func performPendingAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case .open(let url):
            NostrBrowserSession.shared.open(url)
        case .profile(let pubkey):
            navigateTo(ContactPath(key: pubkey), context: containerID)
        case nil:
            break
        }
    }

    private var appIconPlaceholder: some View {
        Color(.secondarySystemBackground)
            .overlay {
                Image(systemName: "app")
                    .font(.title2)
                    .foregroundColor(theme.secondary)
            }
    }

}

#Preview {
    NBNavigationStack {
        AppRow(app: SuggestedApp(
            id: "1", name: "Nostur", description: "A Nostr client",
            openUrl: URL(string: "https://nostur.com")!
        ))
        .padding(10)
    }
}
