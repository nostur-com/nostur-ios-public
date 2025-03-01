//
//  EmbeddedVideoView.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2025.
//

import SwiftUI
import Nuke
import NukeVideo

struct EmbeddedVideoView: View {
    
    @StateObject var vm = EmbeddedVideoVM()
    
    public let url: URL
    public let pubkey: String
    public var nrPost: NRPost?
    public let availableWidth: CGFloat
    public var availableHeight: CGFloat?
    public var metaDimension: CGSize? // Dimensions from meta data (imeta or other)
    public let autoload: Bool
    public let theme: Theme
    @Binding var didStart: Bool
    public var thumbnail: URL?
    
    var body: some View {
        switch vm.viewState {
        case .initial:
            theme.listBackground
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    if let thumbnail {
                        SingleMediaViewer(url: thumbnail, pubkey: "", imageWidth: availableWidth, autoload: true)
                    }
                }
                .overlay {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text(0, format:.percent)
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                vm.cancel()
                            }
                    }
                }
                .onAppear {
                    vm.load(url, nrPost: nrPost)
                }
        case .loading(let percent):
            theme.listBackground
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text(percent, format:.percent)
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                vm.cancel()
                            }
                    }
                }
        case .loadedFirstFrame(let firstFrame):
            theme.listBackground
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    Image(uiImage: firstFrame.uiImage)
                        .resizable()
                        .scaledToFit()
//                        .scaledToFill()
                        .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
//                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .overlay(alignment: .bottomLeading) {
                            if let durationString = firstFrame.durationString {
                                Text(durationString)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                    .padding(3)
                                    .background(.black)
                                    .padding(5)
                            }
                        }
                }
                .overlay(alignment: .center) {
                    if vm.downloadProgress == 0 {
                        Button(action: {
                            vm.startPlaying()
                        }) {
                            Image(systemName:"play.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .contentShape(Rectangle())
                        }
                    }
                    else {
                        HStack(spacing: 5) {
                            ProgressView()
                            Text(vm.downloadProgress, format:.percent)
                                .frame(width: 48, alignment: .leading)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    vm.cancel()
                                }
                        }
                    }
                }
        case .playingInPIP:
            Color.black
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    Image(systemName: "pip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100)
                        .foregroundColor(Color.gray)
                }
                .onReceive(receiveNotification(.stopPlayingVideo)) { _ in
                    vm.didStopPlaying()
                }
//                .onReceive(receiveNotification(.stopPlayingVideo)) { _ in
//                    didStart = false
//                }
        case .loadedFullVideo(let cachedVideo):
            theme.listBackground
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay(alignment: .center) {
                    if didStart {
                        VideoViewurRepresentable(url: url, asset: cachedVideo.asset, isPlaying: $vm.isPlaying, isMuted: $vm.isMuted)
                            .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                                let otherUrl = notification.object as! String
                                if url.absoluteString != otherUrl {
                                    vm.isPlaying = false
                                }
                            }
                            .onDisappear {
                                vm.isPlaying = false
                            }
                    }
                    else {
                        ZStack {
                            if let firstFrame = (vm.cachedFirstFrame?.uiImage ?? cachedVideo.firstFrame) {
                                Image(uiImage: firstFrame)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                                    .overlay(alignment: .bottomLeading) {
                                        if let durationString = cachedVideo.durationString {
                                            Text(durationString)
                                                .foregroundColor(.white)
                                                .fontWeight(.bold)
                                                .padding(3)
                                                .background(.black)
                                                .padding(5)
                                        }
                                    }
                            }
                            
                            Button(action: {
                                vm.startPlaying()
                            }) {
                                Image(systemName:"play.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    
                }
        case .streaming(let streamingUrl):
            theme.listBackground
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    Text("streaming")
                }
        default:
            Text("default")
        }
    }
}

@available(iOS 18.0, *)
#Preview("NosturVideoViewur") {
    @Previewable @State var didStart = false
    VStack {
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
        let m3u8testUrl = URL(string: "https://cdn.stemstr.app/stream/87b5962ef9e37845c72ae0fa2748e8e5b1b257274e8e2e0a8cdd5d3b5e5ff596.m3u8")!
        let videoUrl = URL(string: "https://m.primal.net/OErQ.mov")!
        
        EmbeddedVideoView(url: videoUrl, pubkey: "dunno", availableWidth: UIScreen.main.bounds.width, autoload: true, theme: Themes.default.theme, didStart: $didStart)
    }
}
