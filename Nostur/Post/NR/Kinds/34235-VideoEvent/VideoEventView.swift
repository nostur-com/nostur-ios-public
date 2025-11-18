//
//  VideoEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/12/2023.
//

import SwiftUI
import NukeUI

struct VideoEventView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.availableWidth) private var availableWidth
    
    public let title: String
    public let url: URL
    
    public var summary: String?
    public var imageUrl: URL?
    public var thumb: String?
    
    public var autoload: Bool = false
    
    static let aspect: CGFloat = 16/9
    
    var body: some View {
        if autoload {
            Group {
                VStack(alignment: .leading, spacing: 5) {
                    if let imageUrl {
                        MediaContentView(
                            galleryItem: GalleryItem(url: imageUrl),
                            availableWidth: availableWidth,
                            placeholderAspect: 16/9,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                    }
                    else {
                        Image(systemName: "movieclapper")
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .foregroundColor(Color.gray)
                            .frame(width: DIMENSIONS.PREVIEW_HEIGHT * Self.aspect)
                            .onTapGesture {
                                openURL(url)
                            }
                    }
                    if #available(iOS 16.0, *) {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeight(.bold)
                            .padding(5)
                    }
                    else {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .padding(5)
                    }
                    
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .lineLimit(30)
                            .font(.caption)
                            .padding(5)
                    }
                    
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(5)
//                            .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.listBackground)
            }
            .onTapGesture {
                openURL(url)
            }
        }
        else {
            Text(url.absoluteString)
                .foregroundColor(theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    openURL(url)
                }
        }
    }
}

struct VideoEventView2: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.nxViewingContext) private var nxViewingContext
    
    public let pubkey: String
    public let title: String
    public let url: URL
    
    public var summary: String?
    public var imageUrl: URL?
    
    public var autoload: Bool = false
    public var isNSFW: Bool = false
    public var zoomableId: String = "Default"
    
    @State var isPlaying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VideoFeedItemView(videoURL: url)
//                    EmbeddedVideoView(url: url, pubkey: pubkey, autoload: autoload)
//                    EmbeddedVideoView(url: url, pubkey: pubkey, availableHeight: 640, metaDimension: .init(width: 640, height: 640), autoload: true, thumbnail: imageUrl)
//                        .environment(\.availableWidth, availableWidth + (vc.fullWidthImages ? 20 : 0))
//                        .padding(.horizontal, vc.fullWidthImages ? -10 : 0)
//                        .overlay {
//                            if !isPlaying {
//                                if let imageUrl {
//                                    MediaContentView(
//                                        galleryItem: GalleryItem(url: imageUrl),
//                                        availableWidth: availableWidth,
//                                        placeholderAspect: 4/3,
//                                        maxHeight: 800,
//                                        contentMode: .fit,
//                                        autoload: autoload,
//                                        isNSFW: isNSFW,
//                                        generateIMeta: nxViewingContext.contains(.preview),
//                                        zoomableId: zoomableId
//                                    )
//                                    .padding(.horizontal, -10)
//                                    .padding(.vertical, 10)
//                                }
//                                else {
//                                    Image(systemName: "movieclapper")
//                                        .resizable()
//                                        .scaledToFit()
//                                        .padding()
//                                        .foregroundColor(Color.gray)
//                                        .frame(width: DIMENSIONS.PREVIEW_HEIGHT * 4/3)
//                                        .onTapGesture {
//                                            openURL(url)
//                                        }
//                                }
//                            }
//                        }
            
            Text(title)
                .lineLimit(2)
                .layoutPriority(1)
                .fontWeightBold()
                .padding(5)
            
            if let summary, !summary.isEmpty {
                Text(summary)
                    .lineLimit(30)
                    .font(.caption)
                    .padding(5)
            }
            
            Text(url.absoluteString)
                .foregroundColor(theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    openURL(url)
                }
        }
        .background(theme.listBackground)
        .onTapGesture {
            isPlaying = true
        }
    }
}

#Preview("Vine") {
    PreviewContainer({ pe in
        
    }) {
        PostOrThread(
            nrPost: testNRPost(###"{"id":"82bb357dc59d3361bbf6ff768513e8f5e4eed5504ab6656c4c3c665618765266","pubkey":"7306f0459d42ed3b50926256710beb8ef031a80b659aa9ae819ec4fab4bd8812","created_at":1763330209,"kind":34236,"tags":[["d","684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1"],["imeta","url https://cdn.divine.video/684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1.mp4","m video/mp4","image https://cdn.divine.video/bcd371cc9bb42efaab5cdb5afd70b90523043924652a02a5347ae8f894706c83.jpg","size 1070110","x 684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1","blurhash LEE_,9WANGjY}=NKRkazENn$oeWB"],["title","70s bathroom"],["summary","🤔"],["t","vine"],["t","nostr"],["client","openvine"],["published_at","1763330239"],["duration","3"],["alt","70s bathroom"],["verification","verified_web"],["proofmode","{\"videoHash\":\"684ee62db8db6347a4a1ef27a23c363f1129a65efa4930d8f7e17a4be3b4b5b1\",\"pgpSignature\":\"-----BEGIN PGP SIGNATURE-----\\nVersion: BCPG v1.71\\n\\niQIcBAABCAAGBQJpGkh4AAoJEGJlPhmNpi91J3MP/jGMnOE8IsjV6fx4uJ2sKxjm\\n4yXcSfnkukMqX0tJu5tnz02LS0UveFDq21y5S8Ffea0pZmX4bLa6YlgzahSunfoU\\nWN4E0ukfLa46HpfXnz4h9+xvMfsFCW8MuvW3kRtG9BhHiZvFXCQFHmkWbnuMdAIC\\nVPKpeZxB7VUTV2dN1O4ErBgN1ylPzuSzwk12+6fJ7PEi4lGnLYBhWC1BROYVsWqh\\nse3AFisRTUsth3OAwGGITmysq3mn9zsQrLdrR553vx9OO3HZwzZOjrjWTZONfEgj\\nGWgI8lXE4ros60Fdyk4xOYY8ibPgIrpmZgHkIekhVmxq1BDuW1kIClHZJ+E9+JPc\\n48H71cliGJlfK4PBgeNtS2fL1WIWkPE6i7qqRk2+OClvZ8kH2YJt/zAW43sU3guQ\\nP7DVv/S3M8pOVLEEbiD9KLhIlsH3izBr1pV8T9i+K54W5IJyflvzX4pQEv6Ig6Sb\\ngHk8kz4Nx6sXsDRQXFTbryLruahR9UzRBYL2pR4n5YroJ8hG+yQ150XCGuZ4MnKB\\n7pqbrn/zT2mJDVa1CkNKCeFZydAZk9J0VWMNVk3mSXffiwv4VQnBMjHmooUWKeic\\nnpgR53qcCWbIizipud+2MyKzfDZ96iBqAq6DaEJR2w0CiLLgzPmZnGHX7MkxYzWI\\ngAOwdQcsl0blct3j0+VY\\n=6Oo/\\n-----END PGP SIGNATURE-----\\n\"}"]],"content":"🤔","sig":"217d837c4c9e4c1112c65b3b50e9cd1407d3e85936c4891d4459a4c85b366b874c7bd9f3c082e8d374fe4cc661836f6f276c115842146fdbdcda48255872a839"}"###),
            theme: Themes.default.theme)
    }
}

#Preview("Vine 2") {
    PreviewContainer({ pe in
        
    }) {
        PostOrThread(
            nrPost: testNRPost(###"{"kind":34236,"id":"26eff0b456d3f9b0030f6897aa0f23c5fc7f52301e468d836c6c3347f3f805f0","tags":[["d","97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7"],["imeta","url https://cdn.divine.video/97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7.mp4","url https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/playlist.m3u8","m video/mp4","image https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/thumbnail.jpg","size 1001958","x 97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7","blurhash LjGRPYbDM_xZ0gxZxrWY$ut7bJRn"],["title",""],["summary",""],["client","openvine"],["published_at","1763406697"],["duration","6"],["alt",""]],"sig":"de5345eda729e1c52ef38685440f2e52812c05216723c9227e811764766e741b0e621b86359879278a7bcfdefde906349c0311000702cd132cd5dcde85215b89","created_at":1763406667,"content":"","pubkey":"a0e998aaf688a5ee796384212681c670446c430fd60bf9e942606d68ab564324"}"###),
            theme: Themes.default.theme)
    }
}

#Preview {
    VideoEventView(title: "Categorias de Aristóteles", url: URL(string: "https://www.youtube.com/watch?v=je-n0Ro-B5k")!, summary: "", imageUrl: URL(string: "https://i3.ytimg.com/vi/je-n0Ro-B5k/hqdefault.jpg")!, autoload: true)
}


func parseVideoIMeta(_ tag: FastTag) -> (url: String?, duration: Int?, blurhash: String?, poster: String?) {
    guard tag.0 == "imeta" else { return (url: nil, duration: nil, blurhash: nil, poster: nil) }
    
    var url: String? = nil
    var duration: Int? = nil
    var poster: String? = nil
    var blurhash: String? = nil
    
    // Iterate through optional fields (2–9)
    for field in [tag.1, tag.2, tag.3, tag.4, tag.5, tag.6, tag.7, tag.8, tag.9] {
        guard let value = field else { continue }
        let components = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let key = components.first else { continue }
        guard let value = components.dropFirst().first else { continue }
        
        switch key {
        case "url":
            url = String(value)
        case "image":
            poster = String(value)
        case "blurhash":
            blurhash = String(value)
        case "duration":
            duration = Int(value)
        default:
            continue
        }
    }
    
    return (url: url, duration: duration, blurhash: blurhash, poster: poster)
}



import SwiftUI
import AVKit

// MARK: - Reusable Smooth Video Player (TikTok-style)
struct SmoothVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    
    // Shared player pool to recycle AVPlayers (critical for performance)
    private static var playerPool: [AVPlayer] = []
    private static let queue = DispatchQueue(label: "com.videofeed.playerpool")
    
    // Reuse or create player
    private static func getPlayer(for url: URL) -> AVPlayer {
        queue.sync {
            // Try to reuse an existing player with the same URL
            if let existing = playerPool.first(where: { ($0.currentItem?.asset as? AVURLAsset)?.url == url }) {
                if let index = playerPool.firstIndex(of: existing) {
                    playerPool.remove(at: index)
                }
                existing.seek(to: .zero)
                existing.volume = 1.0
                return existing
            }
            
            // Create new player with buffering optimizations
            let player = AVPlayer()
            player.isMuted = false
            player.automaticallyWaitsToMinimizeStalling = true
            
            // Aggressive prefetching
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            
            // Pre-buffer as much as possible
            player.currentItem?.preferredForwardBufferDuration = 10
            
            return player
        }
    }
    
    // Return player to pool when done
    private static func returnPlayer(_ player: AVPlayer) {
        queue.async {
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerPool.append(player)
            // Keep pool reasonable size
            if playerPool.count > 8 {
                playerPool.removeFirst()
            }
        }
    }
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        
        // Critical for smoothness
        controller.player = Self.getPlayer(for: url)
        
        // Observe when video reaches end → loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: controller.player?.currentItem,
            queue: .main
        ) { _ in
            controller.player?.seek(to: .zero)
            if isPlaying {
                controller.player?.play()
            }
        }
        
        context.coordinator.playerController = controller
        context.coordinator.player = controller.player
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let player = uiViewController.player else { return }
        
        if isPlaying {
            player.playImmediately(atRate: 1.0)  // Bypasses some buffering delays
        } else {
            player.pause()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerController: AVPlayerViewController?
        @Binding var isPlaying: Bool
        
        init(isPlaying: Binding<Bool>) {
            self._isPlaying = isPlaying
        }
        
        deinit {
            if let player = player {
                SmoothVideoPlayer.returnPlayer(player)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    // Clean up on disappear
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
    }
}

// MARK: - Usage Example (in your feed)
struct VideoFeedItemView: View {
    @Environment(\.availableHeight) var availableHeight: CGFloat
    @Environment(\.availableWidth) var availableWidth: CGFloat
    let videoURL: URL
    @State private var isVisible = false
    
    var body: some View {
        SmoothVideoPlayer(url: videoURL, isPlaying: $isVisible)
            .frame(width: availableWidth, height: availableHeight)
            .onAppear {
//                isVisible = true
            }
            .onDisappear {
                isVisible = false
            }
    }
}

func prefetchNextVideos(at index: Int, urls: [URL]) {
    let nextURLs = Array(urls.suffix(from: index + 1).prefix(3))
    for url in nextURLs {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) { /* primed */ }
    }
}


@available(iOS 26.0, *)
#Preview("Vine 3") {
    @Previewable @Environment(\.theme) var theme
    @Previewable @State var nrPost = testNRPost(###"{"kind":34236,"id":"26eff0b456d3f9b0030f6897aa0f23c5fc7f52301e468d836c6c3347f3f805f0","tags":[["d","97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7"],["imeta","url https://cdn.divine.video/97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7.mp4","url https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/playlist.m3u8","m video/mp4","image https://stream.divine.video/678778b3-b8a3-4a57-ac34-6f046907aab0/thumbnail.jpg","size 1001958","x 97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7","blurhash LjGRPYbDM_xZ0gxZxrWY$ut7bJRn"],["title",""],["summary",""],["client","openvine"],["published_at","1763406697"],["duration","6"],["alt",""]],"sig":"de5345eda729e1c52ef38685440f2e52812c05216723c9227e811764766e741b0e621b86359879278a7bcfdefde906349c0311000702cd132cd5dcde85215b89","created_at":1763406667,"content":"","pubkey":"a0e998aaf688a5ee796384212681c670446c430fd60bf9e942606d68ab564324"}"###)
    PreviewContainer({ pe in
        
    }) {
        PreviewApp {
            ScrollView {
                LazyVStack {
//                    Color.random
//                        .frame(height: 400)
                    
                    VideoPostLayout(nrPost: nrPost, theme: theme) {
                        VideoFeedItemView(videoURL: URL(string: "https://cdn.divine.video/97a09d5ad5874c1234c2d4f8cab1001895582afbda3b48e97513b00f79cd54b7.mp4")!)
                    }
                    
//                    Color.random
//                        .frame(height: 400)
//                    
//                    Color.random
//                        .frame(height: 400)
                }
            }
        }
    }
}

struct VideoPost: View {
    let nrPost: NRPost
    let theme: Theme
    
    var body: some View {
        VideoPostLayout(nrPost: nrPost, theme: theme) {
            if let url = nrPost.eventUrl {
                VideoFeedItemView(videoURL: url)
            }
        }
    }
}

struct VideoPostLayout<Content: View>: View {
    let nrPost: NRPost
    let theme: Theme
    @ViewBuilder var content: Content

    
    var body: some View {
        self.content
            // Post menu
            .overlay(alignment: .topTrailing) {
                PostMenuButton(nrPost: nrPost, theme: theme)
                    .offset(x: -25, y: 25)
            }
        
            // Post info
            .overlay(alignment: .bottomLeading) {
                VStack {
                    if let title = nrPost.eventTitle {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeightBold()
                            .padding(5)
                    }
                    
                    ContentRenderer(nrPost: nrPost, showMore: .constant(false))
                    
                    if let summary = nrPost.eventSummary, !summary.isEmpty {
                        Text(summary)
                            .lineLimit(30)
                            .font(.caption)
                            .padding(5)
                    }
                }
            }
        
            // Buttons
            .overlay(alignment: .bottomTrailing) {
                VideoPostButtons(nrPost: nrPost, theme: theme)
                    .padding(.horizontal, 10)
                    .frame(width: 60)
            }
    }
}

struct VideoPostButtons: View {
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var vmc: ViewModelCache = .shared
    private var theme: Theme

    private let nrPost: NRPost
    private var isDetail = false
    private let isItem: Bool
    
    init(nrPost: NRPost, isDetail: Bool = false, isItem: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isDetail = isDetail
        self.isItem = isItem
        self.theme = theme
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            postButtons
            
            // UNDO SEND AND SENT TO RELAYS
            if nrPost.ownPostAttributes.isOwnPost { // TODO: fixme
//                OwnPostFooter(nrPost: nrPost)
//                    .offset(y: 14)
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 16)
        .foregroundColor(theme.footerButtons)
        .font(.system(size: 14))
    }
    
    @ViewBuilder
    private var postButtons: some View {
        VStack(spacing: 0.0) {
            Spacer()
            ForEach(vmc.buttonRow) { button in
                switch button.id {
                case "💬":
                    VideoReplyButton(nrPost: nrPost, isDetail: isDetail, theme: theme)
                case "🔄":
                    VideoRepostButton(nrPost: nrPost, theme: theme)
                case "+":
                    VideoEmojiButton(nrPost: nrPost, theme: theme)
                case "⚡️", "⚡": // These are different. Apple Emoji keyboard creates \u26A1\uFE0F, but its the same as \u26A1 🤷‍♂️
                    if IS_NOT_APPSTORE { // Only available in non app store version
                        VideoZapButton(nrPost: nrPost, theme: theme)
                            .opacity(nrPost.contact.anyLud ? 1 : 0.3)
                            .disabled(!(nrPost.contact.anyLud))
                    }
                    else {
                        EmptyView()
                    }
                case "🔖":
                    VideoBookmarkButton(nrPost: nrPost, theme: theme)
                default:
                    VideoReactionButton(nrPost: nrPost, reactionContent:button.id)
                }
            }
        }
        .font(.system(size: 30))
    }
}

import NavigationBackport

@available(iOS 26.0, *)
struct PreviewApp<Content: View>: View {
    @Environment(\.theme) private var theme
    
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject private var settings: SettingsStore = .shared
    
    @State var selectedTab: String = "Main"
    @ViewBuilder var content: Content
    
    var body: some View {
        
        TabView(selection: $selectedTab) {
            Tab(value: "Main") {
                NBNavigationStack {
                    GeometryReader { geo in
                        self.content
                            .environment(\.availableHeight, geo.size.height)
                            .environment(\.availableWidth, geo.size.width)
                    }
                    .background(theme.listBackground)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            HStack(spacing: 10) {
                                PFP(pubkey: la.account.publicKey, account: la.account, size: 30)
                            }
                        }
                        .sharedBackgroundVisibility(.hidden)
                        
                        ToolbarItem(placement: .title) {
                            Text("Preview App")
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if settings.lowDataMode {
                                Image(systemName: "tortoise")
                                    .foregroundColor(theme.accent.opacity(settings.lowDataMode ? 1.0 : 0.3))
                                    .onTapGesture {
                                        settings.lowDataMode.toggle()
                                        sendNotification(.anyStatus, ("Low Data mode: \(settings.lowDataMode ? "enabled" : "disabled")", "APP_NOTICE"))
                                    }
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                                    sendNotification(.showFeedToggles)
                                }
                                Button(String(localized: "Low Data Mode", comment: "Menu item"), systemImage: "tortoise") {
                                    settings.lowDataMode.toggle()
                                    sendNotification(.anyStatus, ("Low Data mode: \(settings.lowDataMode ? "enabled" : "disabled")", "APP_NOTICE"))
                                }
                            } label: {
                                Label("Feed options", systemImage: "ellipsis")
                                    .labelStyle(.iconOnly)
                                    .foregroundColor(theme.accent)
                                
//                                    Image(systemName: "elipsis")
//                                        .foregroundColor(theme.accent)
//                                        .onTapGesture {
//                                            sendNotification(.showFeedToggles)
//                                        }
                            }

                        }
                    }
                }
            } label: {
                Label("Home", systemImage: "house")
                    .labelStyle(.iconOnly)
            }
            
            Tab(value: "Bookmarks") {
                EmptyView()
            } label: {
                Label("Bookmarks", systemImage: "bookmark")
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
            }
            
            Tab(value: "Search") {
                EmptyView()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            
            Tab(value: "Notifications") {
                EmptyView()
            } label: {
                Label("Notifications", systemImage: "bell.fill")
                    .labelStyle(.iconOnly)
            }
            .badge(3)
            
            Tab(value: "New Post", role: .search) {
                Spacer()
                    .onAppear { selectedTab = "Main" }
            } label: {
                Label(String(localized:"New post", comment: "Button to create a new post"), systemImage: "plus")
                    .fontWeightBold()
                    .labelStyle(.iconOnly)
                    .foregroundStyle(theme.accent)
                    .tint(theme.accent)
            }
            .hidden(selectedTab != "Main")

        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .edgesIgnoringSafeArea(.all)
        .toolbarBackground(.hidden, for: .bottomBar)
        
    }
}
