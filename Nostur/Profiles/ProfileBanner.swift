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
    @ObservedObject var contact:Contact
    var offset:CGFloat
    
    var body: some View {
//        GeometryReader { bannerGEO in
        GeometryReader { geo in
            if let banner = contact.banner {
                if (banner.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                    LazyImage(url: URL(string: banner)) { state in
                        if let container = state.imageContainer {
                            if container.type == .gif, let gifData = container.data {
                                AnimatedGifView(gifData: gifData, width: geo.size.width, height: 150)
                                    .frame(width: geo.size.width, height: 150)
                                    .clipped()
                                    .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                                
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: 150)
                                    .clipped()
                                    .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                            }
                            else {
                                HStack {
                                    Rectangle()
                                        .foregroundColor(.gray)
                                        .frame(width: geo.size.width, height: 150)
                                        .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                                }
                            }
                        }
                        else {
                            HStack {
                                Rectangle()
                                    .foregroundColor(.gray)
                                    .frame(width: geo.size.width, height: 150)
                                    .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
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
                                .frame(height: 150)
                                .clipped()
                                .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                        }
                        else {
                            HStack {
                                Rectangle()
                                    .foregroundColor(.gray)
                                    .frame(height: 150)
                                    .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                            }
                        }
                    }
                    .pipeline(ImageProcessing.shared.banner)
                }
            }
            else {
                HStack {
                    Rectangle()
                        .foregroundColor(.gray)
                        .frame(height: 150)
                        .scaleEffect(1 + max(0,offset / 150 ), anchor: .bottom)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

struct ProfileBanner_Previews: PreviewProvider {
    static var previews: some View {
        if let contact = PreviewFetcher.fetchContact() {
            ProfileBanner(contact: contact, offset: 0)
        }
    }
}
