//
//  DiscoverCommunities.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import SwiftUI
import CoreGraphics
import UIKit
import Nuke
import NukeUI

struct DiscoverCommunities: View {
    @StateObject var vm = Communities()
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.systemBackground
            VStack(alignment: .leading) {
                Text("Discover Communities", comment: "Heading above list of communities")
                    .font(.title)
                
                if !vm.newCommunities.isEmpty && !vm.showNewCommunities {
                    HStack {
                        Text("There are \(vm.newCommunities.count) new communities")
                        Button("Show") {
                            vm.showNewCommunities = true
                        }
                    }
                }
                
                if vm.showNewCommunities {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(vm.newCommunities) { community in
                                HStack(alignment: .top) {
                                    CommunityImage(pictureUrl: community.image, size: 75.0)
                                    Text(community.title)
                                    Text(community.pubkey)
                                }
                                .background(Color.random)
                            }
                        }
                    }
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(vm.communities) { community in
                            HStack(alignment: .top) {
                                CommunityImage(pictureUrl: community.image, size: 75.0)
                                Text(community.title)
                                Text(community.pubkey.prefix(11))
                            }
                            .background(Color.random)
                        }
                    }
                }
            }
            .onAppear {
                vm.loadCommunities() // local
                vm.fetchCommunities() // check for new.
            }
        }
        .navigationTitle(String(localized:"Communities", comment: "Navigation title for Communities view"))
    }
}

struct DiscoverCommunities_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadCommunities() }){
            DiscoverCommunities()
                .padding()
        }
    }
}

struct CommunityImage: View {
    
    var pictureUrl:String?
    var size:CGFloat = 75.0
    var color = Color.gray
    
    var body: some View {
        if let pictureUrl, pictureUrl.prefix(7) != "http://" {
            LazyImage(
                request:
                    ImageRequest(
                        url: URL(string:pictureUrl),
                        processors: [
                            .resize(size: CGSize(width: size, height: size),
                                    unit: .points,
                                    contentMode: .aspectFill,
                                    crop: true,
                                    upscale: true)],
                        userInfo: [.scaleKey: UIScreen.main.scale])
            ) { state in
                if let image = state.image {
                    if state.imageContainer?.type == .gif {
                        image
                            .interpolation(.none)
                            .resizable() // BUG: Still .gif gets wrong dimensions, so need .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    else {
                        image.interpolation(.none)
                    }
                }
                else { color }
            }
            .pipeline(ImageProcessing.shared.communities)
            .frame(width: size, height: size)
            .cornerRadius(8)
//            .background(
//                Circle()
//                    .strokeBorder(.regularMaterial, lineWidth: 5)
//                    .background(Circle().fill(Color.systemBackground))
//            )
        }
        else {
            Rectangle().foregroundColor(color)
                .frame(width: size, height: size)
                .cornerRadius(8)
//                .background(
//                    Rectangle()
//                        .strokeBorder(.regularMaterial, lineWidth: 5)
//                        .background(Circle().fill(Color.systemBackground))
//                )
        }
    }
}
