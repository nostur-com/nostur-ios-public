//
//  ProfileBanner.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct ProfileBanner: View {
    @ObservedObject private var settings:SettingsStore = .shared
    @Environment(\.theme) private var theme
    public var banner:String?
    public var width:CGFloat
    public let BANNER_HEIGHT = 150.0
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        GeometryReader { geoBanner in
            if !settings.lowDataMode, let banner {
                if (banner.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: URL(string: banner)) { state in
                        if let container = state.imageContainer {
                            if !ProcessInfo.processInfo.isLowPowerModeEnabled, container.type == .gif, let gifData = container.data {
                                GIFImage(data: gifData, isPlaying: .constant(true))
//                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .clipped()
                                    .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .clipped()
                                    .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                            }
                            else {
                                HStack {
                                    LinearGradient(
                                        gradient: Gradient(colors: [theme.listBackground, theme.accent]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                                }
                            }
                        }
                        else {
                            HStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [theme.listBackground, theme.accent]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(width: width, height: BANNER_HEIGHT)
                                .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                            }
                        }
                    }
                    .pipeline(ImageProcessing.shared.banner) // NO PROCESSING FOR ANIMATED GIF (BREAKS ANIMATION)
                    .priority(.low) // lower prio for animated gif, saves bandwidth?
                }
                else {
                    LazyImage(url: URL(string: banner)) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: width, height: BANNER_HEIGHT)
                                .clipped()
                                .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                        }
                        else {
                            HStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [theme.listBackground, theme.accent]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(width: width, height: BANNER_HEIGHT)
                                .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                            }
                        }
                    }
                    .pipeline(ImageProcessing.shared.banner)
                }
            }
            else {
                HStack {
                    LinearGradient(
                        gradient: Gradient(colors: [theme.listBackground, theme.accent]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(width: width, height: BANNER_HEIGHT)
                    .scaleEffect(1 + max(0, geoBanner.frame(in:.global).minY / BANNER_HEIGHT ), anchor: .bottom)
                }
            }
        }
        .frame(height: BANNER_HEIGHT)
        .ignoresSafeArea(edges: .top)
    }
}

import NavigationBackport

struct ProfileBanner_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NBNavigationStack {
                if let contact = PreviewFetcher.fetchContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    ProfileBanner(banner:contact.banner, width: UIScreen.main.bounds.width)
                }
            }
        }
    }
}
