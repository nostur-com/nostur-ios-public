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
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    if let thumbnail {
                        MediaContentView(
                            galleryItem: GalleryItem(url: thumbnail),
                            availableWidth: availableWidth,
                            placeholderAspect: 16/9,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                        .allowsHitTesting(false)
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
                    vm.load(url, nrPost: nrPost, autoLoad: autoload)
                }
        case .nsfwWarning(let videoUrlString), .lowDataMode(let videoUrlString), .noHttpsWarning(let videoUrlString):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: 95.0)
                .overlay(alignment: .top) {
                    VStack(alignment: .center) {
                        switch vm.viewState {
                        case .nsfwWarning:
                            Text("Content blocked (NSFW)", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                        case .lowDataMode:
                            Text("Loading paused (Low data mode)", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                        case .noHttpsWarning:
                            Text("Content blocked (No HTTPS)", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                        default:
                            Text("Content blocked", comment: "Displayed when media in a post is blocked")
                                .fontWeightBold()
                        }
                        Text(videoUrlString)
                            .fontItalic()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(String(localized: "Load anyway", comment: "Button to show the blocked content anyway")) {
                            if (!IS_IPHONE) {
                                didStart = true // (will increase size of Kind1Both frame, not needed on iPhone floating player)
                            }
                            vm.viewState = .loading(0)
                            vm.downloadProgress = 0
                            vm.load(url, nrPost: nrPost, autoLoad: autoload, loadAnyway: true)
                        }
                        .foregroundColor(theme.accent)
                        .padding(.bottom, 10)
                    }
                    .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if vm.isAudio {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .fontWeightBold()
                            .padding(3)
                            .background(.black)
                            .padding(5)
                    }
                }

        case .loading(_):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    if let thumbnail {
                        MediaContentView(
                            galleryItem: GalleryItem(url: thumbnail),
                            availableWidth: availableWidth,
                            placeholderAspect: 16/9,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    HStack(spacing: 5) {
                        ProgressView()
                        Text(vm.downloadProgress, format: .percent) // percent from case enum is not updating so use @Published var
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: "multiply.circle.fill")
                            .onTapGesture {
                                vm.cancel()
                            }
                    }
                }
        case .loadedFirstFrame(let firstFrame):
            theme.background.opacity(0.7)
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
                            if (!IS_IPHONE) {
                                didStart = true // (will increase size of Kind1Both frame, not needed on iPhone floating player)
                            }
                            vm.startPlaying()
                        }) {
                            Image(systemName:"play.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 65, height: 65)
                                .foregroundColor(theme.accent)
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
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    Image(systemName: "pip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 65)
                        .foregroundColor(Color.gray)
                }
                .onReceive(receiveNotification(.didEndPIP)) { notification in
                    guard let (otherUrl, cachedFirstFrame, cachedVideo) = notification.object as? (String, CachedFirstFrame?, CachedVideo?) else { return }
                    if url.absoluteString == otherUrl {
                        vm.restoreToFirstFrame(cachedFirstFrame: cachedFirstFrame, cachedVideo: cachedVideo)
                    }
                }
        case .loadedFullVideo(let cachedVideo):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay(alignment: .center) {
                    if didStart {
                        EmbeddedAVPlayerRepresentable(url: url, asset: cachedVideo.asset, timeControlStatus: $vm.timeControlStatus, isMuted: $vm.isMuted)
                            .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                                let otherUrl = notification.object as! String
                                if url.absoluteString != otherUrl {
                                    vm.timeControlStatus = .paused
                                }
                            }
                            .onDisappear {
                                vm.timeControlStatus = .paused
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
                                if (!IS_IPHONE) {
                                    didStart = true // (will increase size of Kind1Both frame, not needed on iPhone floating player)
                                }
                                vm.startPlaying()
                            }) {
                                Image(systemName:"play.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 65, height: 65)
                                    .foregroundColor(theme.accent)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    
                }
        case .noPreviewFound(let videoUrlString):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    if SettingsStore.shared.lowDataMode {
                        Text(videoUrlString)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    else if let thumbnail {
                        MediaContentView(
                            galleryItem: GalleryItem(url: thumbnail),
                            availableWidth: availableWidth,
                            placeholderAspect: 16/9,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    if vm.downloadProgress == 0 {
                        Button(action: {
                            if (!IS_IPHONE) {
                                didStart = true // (will increase size of Kind1Both frame, not needed on iPhone floating player)
                            }
                            vm.startPlaying()
                        }) {
                            Image(systemName:"play.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 65, height: 65)
                                .foregroundColor(theme.accent)
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
                .overlay(alignment: .topTrailing) {
                    if vm.isAudio {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .fontWeightBold()
                            .padding(3)
                            .background(.black)
                            .padding(5)
                    }
                }
        case .streaming(let streamingUrl):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : (availableHeight ?? (availableWidth / vm.aspect)))
                .overlay {
                    EmbeddedAVPlayerRepresentable(url: streamingUrl, timeControlStatus: $vm.timeControlStatus, isMuted: $vm.isMuted)
                        .overlay {
                            if !didStart {
                                theme.listBackground
                                    .overlay {
                                        if let thumbnail {
                                            MediaContentView(
                                                galleryItem: GalleryItem(url: thumbnail),
                                                availableWidth: availableWidth,
                                                placeholderAspect: 16/9,
                                                maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                                                contentMode: .fit,
                                                autoload: autoload
                    //                            tapUrl: url
                                            )
                                            .allowsHitTesting(false)
                                        }
                                    }
                                    .overlay {
                                        if vm.downloadProgress == 0 {
                                            Button(action: {
                                                if (!IS_IPHONE) {
                                                    didStart = true // (will increase size of Kind1Both frame, not needed on iPhone floating player)
                                                }
                                                vm.startPlaying()
                                            }) {
                                                Image(systemName:"play.circle")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 65, height: 65)
                                                    .foregroundColor(theme.accent)
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
                            }
                        }
                        .onReceive(receiveNotification(.startPlayingVideo)) { notification in
                            let otherUrl = notification.object as! String
                            if url.absoluteString != otherUrl {
                                vm.timeControlStatus = .paused
                            }
                        }
                        .onDisappear {
                            vm.timeControlStatus = .paused
                        }
                }
                .overlay(alignment: .topTrailing) {
                    if vm.isAudio {
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                            .fontWeightBold()
                            .padding(3)
                            .background(.black)
                            .padding(5)
                    }
                }
        default:
            Text("📽️")
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
