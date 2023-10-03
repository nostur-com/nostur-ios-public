//
//  ProfilePicFullScreenSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/03/2023.
//

import SwiftUI
import NukeUI

struct ProfilePicFullScreenSheet: View {
    
    @Binding var profilePicViewerIsShown:Bool
    public var pictureUrl:URL
    var isFollowing:Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var sharableImage:UIImage? = nil
    @State private var sharableGif:Data? = nil
    
    var body: some View {
        
        let magnifyAndDragGesture = MagnificationGesture()
                    .onChanged { value in
                        let delta = value / self.lastScale
                        self.lastScale = value
                        self.scale *= delta
                    }
                    .onEnded { value in
                        self.lastScale = 1.0
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            self.position.width = self.newPosition.width + value.translation.width
                            self.position.height = self.newPosition.height + value.translation.height
                        }
                        .onEnded { value in
                            self.newPosition = self.position
                        }
                    )
                    .simultaneously(with: DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                        .onEnded { value in
                            L.og.debug("ProfilePicFullScreenSheet: \(value.translation.debugDescription)")
                            switch(value.translation.width, value.translation.height) {
                                    //                    case (...0, -30...30):  print("left swipe")
                                    //                    case (0..., -30...30):  print("right swipe")
                                    //                    case (-100...100, ...0):  print("up swipe")
                                case (-100...100, 0...):  profilePicViewerIsShown = false
                                default:
                                L.og.debug("ProfilePicFullScreenSheet: no clue")
                            }
                        }
                    )
        
        GeometryReader { geo in
            ZStack {
                VStack {
                    HStack {
                        Spacer()
                        if let sharableImage {
                            ShareMediaButton(sharableImage: sharableImage)
                                .zIndex(3)
                        }
                        else if let sharableGif {
                            ShareGifButton(sharableGif: sharableGif)
                                .zIndex(3)
                        }
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(30)
                            .onTapGesture {
                                profilePicViewerIsShown = false
                            }
                    }
                    Spacer()
                }
                .zIndex(30)
                VStack {
                    if (pictureUrl.absoluteString.suffix(4) == ".gif") { // NO ENCODING FOR GIF (OR ANIMATION GETS LOST)
                        LazyImage(url: pictureUrl) { state in
                            if let container = state.imageContainer {
                                if container.type == .gif, let gifData = container.data {
                                    
                                    GIFImage(data: gifData, isPlaying: .constant(true))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .scaleEffect(scale)
                                        .offset(position)
                                        .gesture(magnifyAndDragGesture)
                                        .onTapGesture {
                                            withAnimation {
                                                scale = 1.0
                                            }
                                        }
                                        .onAppear {
                                            sharableGif = gifData
                                        }
                                }
                                else if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .onAppear {
                                            if let image = state.imageContainer?.image {
                                                sharableImage = image
                                            }
                                        }
                                }
                                else {
                                    Text("🧨")
                                }
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.pfp)
                        .priority(.high)
                    }
                    else {
                        LazyImage(url: pictureUrl) { state in
                            if state.imageContainer?.type == .gif, let gifData = state.imageContainer?.data {
                                GIFImage(data: gifData, isPlaying: .constant(true))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(scale)
                                    .offset(position)
                                    .gesture(magnifyAndDragGesture)
                                    .onTapGesture {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    }
                                    .onAppear {
                                        sharableGif = gifData
                                    }
                            }
                            else if let image = state.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(scale)
                                    .offset(position)
                                    .gesture(magnifyAndDragGesture)
                                    .onTapGesture {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    }
                                    .onAppear {
                                        if let image = state.imageContainer?.image {
                                            sharableImage = image
                                        }
                                    }
                            }
                            else {
                                CenteredProgressView()
                            }
                        }
                        .pipeline(ImageProcessing.shared.pfp)
                        .priority(.high)
                    }
                }
                .onTapGesture {
                    profilePicViewerIsShown = false
                }
            }
        }
    }
}

struct ProfilePicFullScreenSheet_Previews: PreviewProvider {
    
    @State static var shown = true
    static var previews: some View {
        NavigationStack {
            ProfilePicFullScreenSheet(
                profilePicViewerIsShown: $shown,
                pictureUrl: URL(string: "https://nostur.com/fabian/profile.jpg")!, isFollowing:true)
        }
    }
}
