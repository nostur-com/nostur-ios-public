//
//  AppDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/01/2024.
//

import SwiftUI
import NukeUI

struct AppDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.containerID) private var containerID
    public var app: SuggestedApp
    private var appName: String { app.name }
    private var appDescription: String? { app.description }
    private var appLogoUrl: URL? { app.logoUrl }
    private var appOpenURL: URL { app.openUrl }
    private var recommendedByPFPs: [(Pubkey, URL)] { app.recommendedBy }
    
    public var onDismiss: () -> Void
    
    @ObservedObject private var ss: SettingsStore = .shared
    @State private var showDetailSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
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
                    Text("Web App")
                        .font(.subheadline)
                        .foregroundColor(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if let appDescription {
                Text(appDescription)
                    .lineLimit(100)
                    .layoutPriority(2)
                    .font(.subheadline)
                    .foregroundColor(theme.secondary)
            }
            
            if !recommendedByPFPs.isEmpty {
                HStack(alignment: .center, spacing: 2) {
                    Spacer()
                    Text("Recommended by")
                        .font(.caption)
                        .foregroundColor(theme.secondary)
                        .offset(x: CGFloat(min(recommendedByPFPs.count,4)) * 10.0 - 20)
                    
                    ForEach(recommendedByPFPs.prefix(4).indices, id:\.self) { index in
                        MiniPFP(pictureUrl: recommendedByPFPs[index].1, size: 30.0)
                            .onTapGesture {
                                navigateTo(ContactPath(key: recommendedByPFPs[index].0), context: containerID)
                            }
                            .id(index)
                            .offset(x: CGFloat(index) * -10 + (recommendedByPFPs.count > 4 ? 20 : 10))
                    }
                    .offset(x: CGFloat(min(recommendedByPFPs.count,4)) * 10.0 - 20)
                    
                    if (recommendedByPFPs.count > 4) {
                        Text("+\(recommendedByPFPs.count - 4)")
                            .font(.caption)
                            .foregroundColor(theme.secondary)
                            .padding(8)
                            .background(theme.secondary.opacity(0.5))
                            .cornerRadius(15)
                            .zIndex(-10)
                    }
                }
            }
            
            Spacer()
            
            Button(action: openApp) {
                Text("Open in \(appName)")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(NosturButton(height: 36))
            .frame(maxWidth: .infinity, alignment: .center)
            
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDismiss() }
            }
        }
    }
    
    private func openApp() {
        openURL(appOpenURL)
        onDismiss()
    }
}

#Preview {
    VStack {
        Group {
            AppDetail(
                app: SuggestedApp(
                        id: "1",
                        name: "Nostur",
                        description: "A nostr client",
                        logoUrl: URL(string: "https://nostur.com/nostur.png")!,
                        openUrl: URL(string: "https://nostur.com")!,
                        recommendedBy: [
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
                        ]), onDismiss: { } )
            
            AppDetail(
                app: SuggestedApp(
                        id: "1",
                        name: "Nostur",
                        description: "A nostr client",
                        logoUrl: URL(string: "https://nostur.com/nostur.png")!,
                        openUrl: URL(string: "https://nostur.com")!,
                        recommendedBy: []), onDismiss: { } )
            
            AppDetail(
                app: SuggestedApp(
                        id: "1",
                        name: "Nostur",
                        description: "A nostr client",
                        logoUrl: URL(string: "https://nostur.com/nostur.png")!,
                        openUrl: URL(string: "https://nostur.com")!,
                        recommendedBy: [
                            (
                                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
                            )
                        ]), onDismiss: { } )
            
            AppDetail(
                app: SuggestedApp(
                        id: "1",
                        name: "Nostur",
                        description: "A nostr client",
                        logoUrl: URL(string: "https://nostur.com/nostur.png")!,
                        openUrl: URL(string: "https://nostur.com")!,
                        recommendedBy: [
                            (
                                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
                            ),
                            (
                                "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                                URL(string: "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972")!
                            )
                        ]), onDismiss: { } )
            
            AppDetail(
                app: SuggestedApp(
                        id: "1",
                        name: "Nostur",
                        description: "A nostr client",
                        logoUrl: URL(string: "https://nostur.com/nostur.png")!,
                        openUrl: URL(string: "https://nostur.com")!,
                        recommendedBy: [
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

                        ]), onDismiss: { } )
        }
        .background(Color.black)
                
    }
    .padding()
    .background(Color.red)
}
