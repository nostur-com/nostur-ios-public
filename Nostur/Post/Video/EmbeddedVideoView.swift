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
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @StateObject var vm = EmbeddedVideoVM()
    
    public let url: URL
    public let pubkey: String
    public var nrPost: NRPost?
    public var availableHeight: CGFloat?
    public var metaDimension: CGSize? // Dimensions from meta data (imeta or other)
    public let autoload: Bool
    public var thumbnail: URL?
    
    private var effectiveAspect: CGFloat {
        if let metaDimension, metaDimension.width > 0, metaDimension.height > 0 {
            return metaDimension.width / metaDimension.height
        }
        return vm.aspect
    }
    
    private var frameHeight: CGFloat {
        availableHeight ?? (availableWidth / effectiveAspect)
    }
    
    private var thumbnailAspect: CGFloat {
        if let metaDimension, metaDimension.width > 0, metaDimension.height > 0 {
            return metaDimension.width / metaDimension.height
        }
        return 16 / 9
    }
    
    var body: some View {
        switch vm.viewState {
        case .initial:
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: frameHeight)
                .overlay {
                    if let thumbnail {
                        MediaContentView(
                            galleryItem: GalleryItem(url: thumbnail),
                            availableWidth: availableWidth,
                            placeholderAspect: thumbnailAspect,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    ProgressView()
                }
                .onAppear {
                    vm.load(url, nrPost: nrPost, autoLoad: autoload, metaDimensions: metaDimension, availableWidth: availableWidth, availableHeight: availableHeight ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                }
        case .loading(let percentage), .paused(let percentage):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: frameHeight)
                .overlay {
                    if let thumbnail {
                        MediaContentView(
                            galleryItem: GalleryItem(url: thumbnail),
                            availableWidth: availableWidth,
                            placeholderAspect: thumbnailAspect,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment:. topTrailing) {
                    if percentage == 0 {
                        ProgressView()
                    }
                    else {
                        Text(vm.downloadProgress, format: .percent)
                        .padding(5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if case .loading(_) = vm.viewState {
                        vm.pause()
                    }
                    else {
                        vm.viewState = .loading(vm.downloadProgress)
                        vm.load(url, nrPost: nrPost, autoLoad: autoload, metaDimensions: metaDimension, availableWidth: availableWidth, availableHeight: availableHeight ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, loadAnyway: true)
                    }
                }
                .overlay {
                    if case .paused(_) = vm.viewState {
                        Button("Resume") {
                            vm.viewState = .loading(vm.downloadProgress)
                            vm.load(url, nrPost: nrPost, autoLoad: autoload, metaDimensions: metaDimension, availableWidth: availableWidth, availableHeight: availableHeight ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, loadAnyway: true)
                        }
                    }
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
                
        case .loadedFirstFrame(let firstFrame):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: frameHeight)
                .overlay {
                    Image(uiImage: firstFrame.uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: availableWidth, height: frameHeight)
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
                        VideoPlayOverlay(size: 88, accentColor: theme.accent)
                            .onTapGesture {
                                vm.startPlaying()
                            }
                    }
                    else {
                        HStack(spacing: 5) {
                            ProgressView()
                            Text(vm.downloadProgress, format:.percent)
                                .frame(width: 48, alignment: .leading)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    vm.pause()
                                }
                        }
                    }
                }
        case .playingInPIP:
            Color.black
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : frameHeight)
                .overlay {
                    Image(systemName: "pip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 65)
                        .foregroundColor(Color.gray)
                }
                .onReceive(receiveNotification(.didEndPIP)) { notification in
                    guard let (otherUrl, cachedFirstFrame) = notification.object as? (String, CachedFirstFrame?) else { return }
                    if url.absoluteString == otherUrl {
                        vm.restoreToFirstFrame(cachedFirstFrame: cachedFirstFrame)
                    }
                }
        case .noPreviewFound(let videoUrlString):
            theme.background.opacity(0.7)
                .frame(width: availableWidth, height: vm.isAudio ? 75.0 : frameHeight)
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
                            placeholderAspect: thumbnailAspect,
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
                        VideoPlayOverlay(size: 88, accentColor: theme.accent)
                            .onTapGesture {
                                vm.startPlaying()
                            }
                    }
                    else {
                        HStack(spacing: 5) {
                            ProgressView()
                            Text(vm.downloadProgress, format: .percent)
                                .frame(width: 48, alignment: .leading)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    vm.pause()
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

        default:
            Text("📽️")
        }
    }
}

struct VideoPlayOverlay: View {
    var size: CGFloat = 88
    var accentColor: Color = .white
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(accentColor)
                .offset(x: size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@available(iOS 18.0, *)
#Preview("NosturVideoViewur") {
    VStack {
        let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
//        let m3u8testUrl = URL(string: "https://cdn.stemstr.app/stream/87b5962ef9e37845c72ae0fa2748e8e5b1b257274e8e2e0a8cdd5d3b5e5ff596.m3u8")!
        let videoUrl = URL(string: "https://m.primal.net/OErQ.mov")!
        
        EmbeddedVideoView(url: videoUrl, pubkey: "dunno", autoload: true)
    }
}
