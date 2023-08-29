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
    @EnvironmentObject var theme:Theme
    var banner:String?
    var width:CGFloat
    var offset:CGFloat
    let BANNER_HEIGHT = 150.0
    
    var body: some View {
        //        let _ = Self._printChanges()
        Group {
            if let banner {
                if (banner.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: URL(string: banner)) { state in
                        if let container = state.imageContainer {
                            if !ProcessInfo.processInfo.isLowPowerModeEnabled, container.type == .gif, let gifData = container.data {
                                GIFImage(data: gifData)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .clipped()
                                    .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .clipped()
                                    .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
                            }
                            else {
                                HStack {
                                    LinearGradient(
                                        gradient: Gradient(colors: [theme.background, theme.accent]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                    .frame(width: width, height: BANNER_HEIGHT)
                                    .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
                                }
                            }
                        }
                        else {
                            HStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [theme.background, theme.accent]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(width: width, height: BANNER_HEIGHT)
                                .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
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
                                .frame(width:width, height: BANNER_HEIGHT)
                                .clipped()
                                .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
                        }
                        else {
                            HStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [theme.background, theme.accent]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(width: width, height: BANNER_HEIGHT)
                            }
                        }
                    }
                    .pipeline(ImageProcessing.shared.banner)
                }
            }
            else {
                HStack {
                    LinearGradient(
                        gradient: Gradient(colors: [theme.background, theme.accent]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(width: width, height: BANNER_HEIGHT)
                    //                        .scaleEffect(1 + max(0,offset / BANNER_HEIGHT ), anchor: .bottom)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct ProfileBanner_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NavigationStack {
                if let contact = PreviewFetcher.fetchContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    ProfileBanner(banner:contact.banner, width: UIScreen.main.bounds.width, offset: 0)
                }
            }
        }
    }
}
