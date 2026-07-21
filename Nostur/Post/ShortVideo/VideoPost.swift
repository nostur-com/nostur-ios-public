//
//  VideoPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/11/2025.
//

import SwiftUI

class VideoPostPlaybackCoordinator: ObservableObject {
    
    @Published var mostVisiblePostID: String? = nil
    private var visibilities: [String: CGFloat] = [:]
    private var userPausedPostIDs: Set<String> = []
    
    func reportVisibility(postID: String, visibility: CGFloat) {
        if visibility > 0.2 {
            visibilities[postID] = visibility
        }
        else {
            visibilities.removeValue(forKey: postID)
        }
        updateMostVisible()
    }
    func removeVisibility(postID: String) {
        visibilities.removeValue(forKey: postID)
        updateMostVisible()
    }
    func markUserPaused(postID: String) {
        userPausedPostIDs.insert(postID)
    }
    func markUserPlaying(postID: String) {
        userPausedPostIDs.remove(postID)
    }
    func canAutoPlay(postID: String) -> Bool {
        !userPausedPostIDs.contains(postID)
    }
    private func updateMostVisible() {
        let most = visibilities.max { a, b in a.value < b.value }
        let newID = most?.key
        if mostVisiblePostID != newID {
            mostVisiblePostID = newID
        }
    }
}

struct VideoPost: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.availableHeight) private var availableHeight: CGFloat
    @Environment(\.availableWidth) private var availableWidth: CGFloat
    @Environment(\.shortVideoAutoplayAudioEnabled) private var shortVideoAutoplayAudioEnabled
    @EnvironmentObject private var coordinator: VideoPostPlaybackCoordinator
    
    public let nrPost: NRPost
    public var isDetail: Bool = false
    public var isEmbedded: Bool = false
    public var isVisible: Bool = true
    public let theme: Theme
    
    @State private var isPlaying = false
    @State private var isMuted = true
    
    private var postID: String { nrPost.id }
    
    @State var canPlay = true
    
    private var videoWidth: CGFloat {
        if nxViewingContext.contains(.postParent) {
            return availableWidth - 20
        }
        return availableWidth
    }
    
    @ViewBuilder
    private var muteButton: some View {
        if !shortVideoAutoplayAudioEnabled {
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
        }
    }
    
    var body: some View {
        VideoPostLayout(nrPost: nrPost, theme: theme) {
            if let videoURL = nrPost.eventUrl {
                if #available(iOS 16.0, *) {
                    ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying, isMuted: $isMuted)
                        .frame(width: videoWidth, height: min((videoWidth*3), availableHeight))
                        .background(Color.black)
                        .frame(width: videoWidth, height: availableHeight)
                        .overlay(alignment: .topLeading) {
                            muteButton
                        }
                        .onTapGesture { togglePlayback() }
                        .modifier {
                            if !isDetail && !nxViewingContext.contains(.preview) {
                                $0.onGeometryChange(for: CGFloat.self) { proxy in
                                    let globalFrame = proxy.frame(in: .global)
                                    let mainScreen = UIScreen.main.bounds
                                    let intersection = globalFrame.intersection(mainScreen)
                                    let visibleArea = intersection.width * intersection.height
                                    let totalArea = globalFrame.width * globalFrame.height
                                    return totalArea > 0 ? visibleArea / totalArea : 0
                                } action: { fraction in
                                    coordinator.reportVisibility(postID: postID, visibility: fraction)
                                }
                                .onAppear {
                                    guard isVisible else { return }
                                    canPlay = true
                                    updateAutoplayState()
                                }
                                .onDisappear {
                                    canPlay = false
                                    //guard isVisible else { return }
                                    coordinator.removeVisibility(postID: postID)
                                    isPlaying = false
                                }
                                .onValueChange(coordinator.mostVisiblePostID) { oldValue, newValue in
                                    guard oldValue != newValue else { return }
                                    guard canPlay && isVisible else { return }
                                    updateAutoplayState()
                                }
                                
                            }
                            else { $0 }
                        }
                } else {
                    GeometryReader { geo in
                        ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying, isMuted: $isMuted)
                            .frame(width: videoWidth, height: min((videoWidth*3), availableHeight))
                            .background(Color.black)
                            .frame(width: videoWidth, height: availableHeight)
                            .overlay(alignment: .topLeading) {
                                muteButton
                            }
                            .onTapGesture { togglePlayback() }
                            .modifier {
                                if !isDetail && !nxViewingContext.contains(.preview) {
                                    $0.onAppear {
                                        canPlay = true
                                        guard isVisible else { return }
                                        updateVisibilityPreiOS16(geo: geo)
                                        updateAutoplayState()
                                    }
                                    .onDisappear {
                                        canPlay = false
                                        guard isVisible else { return }
                                        coordinator.removeVisibility(postID: postID)
                                        isPlaying = false
                                    }
                                    .onChange(of: geo.frame(in: .global)) { _ in
                                        guard isVisible else { return }
                                        updateVisibilityPreiOS16(geo: geo)
                                    }
                                    .onValueChange(coordinator.mostVisiblePostID) { oldValue, newValue in
                                        guard oldValue != newValue else { return }
                                        guard canPlay && isVisible else { return }
                                        updateAutoplayState()
                                    }
                                }
                                else { $0 }
                            }
                    }
                    .frame(width: videoWidth, height: availableHeight)
                }
            }
        }
        .onAppear {
            // Detail has no feed-visibility autoplay; start when opening short-video detail.
            guard isDetail else { return }
            coordinator.markUserPlaying(postID: postID)
            setPlaying(true, muted: !shortVideoAutoplayAudioEnabled)
        }
        .onValueChange(isVisible) { wasVisible, isVisibleNow in
            // When changing feed, don't continue playing
            guard isPlaying && !isVisibleNow else { return }
            setPlaying(false)
        }
        .onReceive(receiveNotification(.voiceMessagePlayerDidStartPlayback)) { _ in
            pauseForExternalPlayback()
        }
        .onReceive(receiveNotification(.stopPlayingVideo)) { _ in
            pauseForExternalPlayback()
        }
        .onReceive(receiveNotification(.shortVideoPlayerDidStartPlayback)) { notification in
            guard let otherPostID = notification.object as? String, otherPostID != postID else { return }
            pauseForExternalPlayback()
        }
//        .onValueChange(coordinator.mostVisiblePostID) { oldId, newId in
//            // When changing feed, don't continue playing
//            guard oldId == postID else  { return }
//            isPlaying = false
//        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            coordinator.markUserPaused(postID: postID)
            setPlaying(false)
        }
        else {
            coordinator.markUserPlaying(postID: postID)
            setPlaying(true, muted: false)
        }
    }
    
    private func updateAutoplayState() {
        let shouldPlay = coordinator.mostVisiblePostID == postID && coordinator.canAutoPlay(postID: postID)
        setPlaying(shouldPlay, muted: !shortVideoAutoplayAudioEnabled)
    }
    
    private func pauseForExternalPlayback() {
        guard isPlaying else { return }
        coordinator.markUserPaused(postID: postID)
        setPlaying(false)
    }
    
    private func setPlaying(_ playing: Bool, muted: Bool = true) {
        guard isPlaying != playing else { return }
        if playing {
            isMuted = muted
            AnyPlayerModel.shared.pauseVideo()
            sendNotification(.shortVideoPlayerDidStartPlayback, postID)
        }
        isPlaying = playing
    }
    
    private func updateVisibilityPreiOS16(geo: GeometryProxy) {
        let globalFrame = geo.frame(in: .global)
        let mainScreen = UIScreen.main.bounds
        let intersection = globalFrame.intersection(mainScreen)
        let visibleArea = intersection.width * intersection.height
        let totalArea = globalFrame.width * globalFrame.height
        let fraction = totalArea > 0 ? visibleArea / totalArea : 0
        coordinator.reportVisibility(postID: postID, visibility: fraction)
    }
}

@available(iOS 26.0, *)
#Preview("Vine") {
    @Previewable @Environment(\.theme) var theme
    @Previewable @State var nrPost5 = testNRPost(###"{"pubkey":"5943c88f3c60cd9edb125a668e2911ad419fc04e94549ed96a721901dd958372","created_at":1763179480,"kind":22,"tags":[["alt","Vertical Video"],["title",""],["published_at","1763179481"],["imeta","url https://blossom.primal.net/cf5a5ff1dddc3b97d8938f33d1088c9e5babcdc3f94c5178112392e9b3a36d27.mp4","m video/mp4","alt Vertical Video","x cf5a5ff1dddc3b97d8938f33d1088c9e5babcdc3f94c5178112392e9b3a36d27","size 3069605","dim 720x1280","blurhash _FF}~1~p%z-p~W0fE2.S?aNH^+xu%gt79ZIV-WWVNaxu-:IpjG%MNHoMsAR,S6kCX5NxofxZNGf,W.slt7X8bFs:%1WARkxFslR*R*xDV@kDjFnOoft7WBs;t7oKafs;of"],["nonce","229","16"]],"id":"0000c09aa7133e2e75e7e352af918c56e7a8cafc4ed456a67a24dc4a9f777272","content":"Marin 💕✨\nOriginally published in: 2025-11-13","sig":"53badb2a42b0b147252b0ac23545773a50ec123c9761da6e910a7c37f046dccae51e7174d5498ff83e4a33987c9a618808b62d7c34b09abaafec4b543b6ed819"}"###)
    @Previewable @State var nrPost2 = testNRPost(###"{"tags":[["d","c28be3983f261297ee055b4ed1941ae9b335241e35421d89dbfdf3eefe372daf"],["imeta","url https://stream.divine.video/fbe3777b-8e5d-4194-ba8d-b2e205a32904/play_480p.mp4","url https://cdn.divine.video/c28be3983f261297ee055b4ed1941ae9b335241e35421d89dbfdf3eefe372daf.mp4","url https://stream.divine.video/fbe3777b-8e5d-4194-ba8d-b2e205a32904/playlist.m3u8","m video/mp4","image https://stream.divine.video/fbe3777b-8e5d-4194-ba8d-b2e205a32904/thumbnail.jpg","size 1493938","x c28be3983f261297ee055b4ed1941ae9b335241e35421d89dbfdf3eefe372daf","blurhash L6C6GXHq9Fx^17D%t7tT5tIUof%M"],["title",""],["summary",""],["client","openvine"],["published_at","1763555171"],["duration","4"],["alt",""],["verification","verified_web"],["proofmode","{\"videoHash\":\"c28be3983f261297ee055b4ed1941ae9b335241e35421d89dbfdf3eefe372daf\",\"pgpSignature\":\"-----BEGIN PGP SIGNATURE-----\\nVersion: BCPG v1.71\\n\\niQIcBAABCAAGBQJpHbc6AAoJEGJlPhmNpi91uJgP/27AoagZ0Cs+JcFL2NjDpe7k\\n8LKYyAcqbDaHtcdSydFl4VlnLRW7cSU3zvWeJcVSp4nOVH4gcC+PDz1zUKdBLOos\\njc/Mv1FWN2K8A9u1J/43J+rMLqxInATp2BXflBFf/fsSf8avHbKQDrGNBeGwRMOm\\nYeXkXLUbpQnh+0ZhAPiKj5vUlBsipZ8dIEyM9fAzitIArp/W26d5Va3VCKH5lf8s\\nKXj58x1u2EMyp4mGxSHRwFOV5X65t3mfsYcQlxtkXwshRRQJWRyI5JEeObtcxU3C\\nm6r6hPaWyEi6lKU5MKgJOT6iWBF2zosX1o4b7O0H+qZlyP+FaLtAozDuASkVnNuo\\n9UhcxX0KY5kRWF7pw9CNTOQ2GW27L/3u4TdSeGXqR9oab9akWq8U+oq9kx1GkEmW\\nfC6JKqSxZ4vjuAhpG0yCMA00rRxEG8JZcUJbQmF0+Cvw9BpvnJI5Qx7JxQhG0zSc\\n9Ndyxe60pCvtZR2v8xUTvFksTxGQeGgg6/boyGxkMi+EYEtWlIgh5q5rZEgqTH/Z\\njC36xurOJQBrg6EKjyYnr55qjCm9zwygEzXVGZHRzSm1bZUgM2ak9iHomd21UeXp\\nZEIQlZa5bA6CJSFiD0yo5yjgyQemvXLQ/WmblQabYiVpXmTNwV1H4FJpGdAXY3W0\\njh8dYZlTPsLdbP98Oed5\\n=0mAk\\n-----END PGP SIGNATURE-----\\n\"}"]],"kind":34236,"content":"","sig":"21a42a15423ffc2cab28eac2f7a1eb219f8fbd8caadedbd9b7ffb1f5042496ea9b02665e4577580678c6ee58bcabd51bd36155d1b2faa52a161070b10ed7dfd0","created_at":1763555141,"pubkey":"77ce56f89d1228f7ff3743ce1ad1b254857b9008564727ebd5a1f317362f6ca7","id":"7461b10041a05a148ccb9314f2ac8a370b7ca25c1bb5f625af3719e08138cc8d"}"###)
    @Previewable @State var nrPost3 = testNRPost(###"{"pubkey":"9f47da7bd83fd1012912d622a76b91404d48460713bcbd412d22d751cd4af6a9","id":"5f1cf60afbe9c3c5272b7a8b9f14901dde5818b8037de8e73a4354c87efa2fd5","sig":"cdf9240a5e4df33e8927acfe4b436513668436d240fd5f65037e787e2bce9788809c59c6f94e8e159c1e5885eb216b531726f5cde63d41820f12b451549c5880","created_at":1763542742,"kind":34236,"content":"","tags":[["d","24f4575762bf45c9c56bdbf84e9c3e6c69cba0a4989d097b5916c98b634dd9d6"],["imeta","url https://stream.divine.video/f44dd1ab-5143-49be-982e-2cfce708b275/play_480p.mp4","url https://cdn.divine.video/24f4575762bf45c9c56bdbf84e9c3e6c69cba0a4989d097b5916c98b634dd9d6.mp4","url https://stream.divine.video/f44dd1ab-5143-49be-982e-2cfce708b275/playlist.m3u8","m video/mp4","image https://stream.divine.video/f44dd1ab-5143-49be-982e-2cfce708b275/thumbnail.jpg","size 329039","x 24f4575762bf45c9c56bdbf84e9c3e6c69cba0a4989d097b5916c98b634dd9d6","blurhash L7Eo_A.9ty4ULVkWx:D%9vxt$*-;"],["title","🪿"],["summary",""],["client","openvine"],["published_at","1763542772"],["duration","1"],["alt","🪿"]]}"###)
    @Previewable @State var nrPost4 = testNRPost(###"{"created_at":1763524451,"kind":34236,"id":"aa7babce662cf7e37f54fb003cf1281cd6531281d61cedf70b69f5923785e472","tags":[["d","6853b35c3f1ca34ef645f0422f7f12a0fc2e41c2d6843f5bfdd792c54e142d05"],["imeta","url https://stream.divine.video/98e3775b-da5b-4334-a77d-5fdaae43b752/play_480p.mp4","url https://cdn.divine.video/6853b35c3f1ca34ef645f0422f7f12a0fc2e41c2d6843f5bfdd792c54e142d05.mp4","url https://stream.divine.video/98e3775b-da5b-4334-a77d-5fdaae43b752/playlist.m3u8","m video/mp4","image https://stream.divine.video/98e3775b-da5b-4334-a77d-5fdaae43b752/thumbnail.jpg","size 1790038","x 6853b35c3f1ca34ef645f0422f7f12a0fc2e41c2d6843f5bfdd792c54e142d05","blurhash LUJHEls8ozNd4TxZofE2xuWCV@of"],["title",""],["summary",""],["client","openvine"],["published_at","1763524481"],["duration","6"],["alt",""]],"sig":"82542fb2f27c373d55d923a1a7f1095e7d81f804227e647f70a5b5b7beb3a1c6c0c9ffe274ceab62677b0d76bcef2dab25910bc065447ab8452b9f3da1d7a173","pubkey":"963368c4f9c0cf140daab566d293530661c4d7d67d03802ba4a5a83fe57964b3","content":""}"###)
    @Previewable @State var nrPost1 = testNRPost(###"{"pubkey":"d95aa8fc0eff8e488952495b8064991d27fb96ed8652f12cdedc5a4e8b5ae540","id":"aee89fd7513f8d47521af565f74b07f5d03b0c4c6fcf1849288486039d702a8f","created_at":1763516777,"kind":34236,"sig":"7709c27a2d88886d0631fd597b444df1092ffc778a369f055c13bba3a75c2092fd0ae89086bf6dd4b4227ca0e0ac945a8239309d11ab19f4626fab8529e4b96a","tags":[["d","8e97d65e2119b013e8a08edbd5ad873a19e334b6832a77687d070d812fc021d4"],["imeta","url https://stream.divine.video/23923e2c-4cc4-4179-95c3-484910983162/play_480p.mp4","url https://cdn.divine.video/8e97d65e2119b013e8a08edbd5ad873a19e334b6832a77687d070d812fc021d4.mp4","url https://stream.divine.video/23923e2c-4cc4-4179-95c3-484910983162/playlist.m3u8","m video/mp4","image https://stream.divine.video/23923e2c-4cc4-4179-95c3-484910983162/thumbnail.jpg","size 2128663","x 8e97d65e2119b013e8a08edbd5ad873a19e334b6832a77687d070d812fc021d4","blurhash L26*H,%50$R%Hqs5J%IXz?o59vt5"],["title",""],["summary",""],["client","openvine"],["published_at","1763516807"],["duration","6"],["alt",""]],"content":""}"###)
    @Previewable @State var nrPost0 = testNRPost(###"{"sig":"d2a31097744da5d832eae04ebfc7a34550734a3cce2c8dcd3d80cdcc6e6e3514b1c6aec8c375f5ce0570f3f3dce2c2676c6417d745459ad1183656da99b9be60","id":"3aae55dda8447723201b0004cd499805f35aa65922539814a26dced9ad3f901d","kind":34236,"created_at":1764602437,"tags":[["d","dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75"],["title","Vine test"],["summary","Fire"],["published_at","1764602437"],["duration","2"],["client","damus"],["url","https://cdn.divine.video/dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75.mp4"],["imeta","url https://cdn.divine.video/dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75.mp4","hls https://cdn.divine.video/dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75.mp4","fallback https://cdn.divine.video/dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75.mp4","m video/mp4","dim 1080x1920","x dbe0753abb1d456f24f22a6b76fe8486ea4ade3cdb9f13a794425a5859fe2b75"]],"content":"Fire","pubkey":"17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4"}"###)
    @Previewable @State var nrPost00 = testNRPost(###"{"id":"13ec35a13b8d433a3db4e5917ff95ff0657e81f73963b53875668df949354a33","kind":34236,"content":"We're jammin' with Theo Katzman backstage here in Oslo.","tags":[["d","e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a"],["imeta","url https://media.divine.video/e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a","m video/mp4","image https://media.divine.video/7c088120e6a37931370efc97715b5c93f4e7230ce8ccc4aa4575a5c2722ab17b","dim 1080x1920","size 13976016","x e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a","blurhash vCByT=-:0f4:Ejj]R*j[Or%2$%IpxGW;%L$%9uNw%2xGtQxaWBWB-os:RjR*"],["title","Nostriches Backstage"],["summary","We're jammin' with Theo Katzman backstage here in Oslo."],["t","Music"],["t","Tunestr"],["L","ISO-639-1"],["l","en","ISO-639-1"],["client","diVine"],["published_at","1780428030"],["duration","6"],["alt","Nostriches Backstage"],["c2pa_manifest_id","urn:c2pa:1cae6e2a-e9b1-47ed-90cf-d2c7a063d7f7"],["verification","verified_mobile"],["proofmode","{\"videoHash\":\"e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a\",\"pgpSignature\":\"-----BEGIN PGP SIGNATURE-----\\nVersion: BCPG v1.71\\n\\niQIcBAABCAAGBQJqHyyXAAoJEIj5rVB6fOBs+akP+wdWPihU9pA659NqiK0o0fkL\\nD+YVUp4+XRk0t1viuOBoTUyiIm+YnCZ4hn+qZAPoz2hn++Dp1TNMorzAouiB0i7T\\nMjGYoud5DaWi6xnJMT2vocWr3sJaaUNssCsAbC8jeEO4aFFaS4CnUX+2q2OSKg4E\\nQrwJlGHR2Z51zxb+J5p/A2nhlh9tOYlwQoSLvE/kHedKfjHY2JgwPzJyhsWrgYXa\\nCqhgf1yEgVHwN5wgl7qfGiyt84GW4PsOqPtJe/CwIXzm677fClBxRlpju79AmjeH\\nLhVgm1GaHLUcEv0mYoaQsV/7/O7YJaOYYuXN587hOmUkBEg9IJhUpcsK9NkpuRNR\\ntC+GMV0QJKcFiMlbB2uV5SQlAa4/NDv2E3xQ9lrn9CQ9qrTcS8uDhwabw/eQQvx1\\nHuRQya+iTLDCXXmxiqIeiyN0A2IkgybZb2UaqhiZ3gPjRf/2rIYoUIt5Pb/cUKqX\\nrGEB7t+067GOBI40xUTaObLLmCsdp4O9170AlQSv63bS/LppPQ78Y9nHL2LODhCh\\nXu50XDozVpjaGw5VUlkeZnWMGdlt9Z0rDw2txgx5gbVNOA3BpNHzP4B4flBbKT/s\\nW9CZUwSPN+XOgcUZn0nUtDKNVtvJZzXt9Eo2kXEeL9eOMOAmLHKG7LRquDOOfALp\\ncJGAyklA8nMaILVaf9zS\\n=PvL4\\n-----END PGP SIGNATURE-----\\n\",\"deviceAttestation\":\"Certificate:\\n    Data:\\n        Version: 3 (0x2)\\n        Serial Number: 1 (0x1)\\n    Signature Algorithm: ecdsa-with-SHA256\\n        Issuer: O=TEE, CN=5f87cced30b59a7cf96327fe53abbd3f\\n        Validity\\n            Not Before: Jan  1 00:00:00 1970 GMT\\n            Not After : Jan  1 00:00:00 2048 GMT\\n        Subject: CN=Android Keystore Key\\n        Subject Public Key Info:\\n            Public Key Algorithm: id-ecPublicKey\\n                Public-Key: (P-256)\\n                pub:\\n                    04:ed:23:83:f4:28:9d:97:7a:1f:97:51:33:e5:3b:\\n                    63:e1:c6:87:70:b4:48:47:fe:b5:34:b1:f9:18:37:\\n                    05:de:bd:a3:9d:96:d7:0a:ac:37:bc:a0:97:8c:47:\\n                    02:98:cf:f3:b1:c3:6f:9a:49:f0:40:17:d1:9e:ce:\\n                    bf:ff:b9:71:e1\\n        X509v3 extensions:\\n            X509v3 Key Usage: critical\\n                Digital Signature\\n            1.3.6.1.4.1.11129.2.1.17: \\n                0..r....\\n......\\n...@e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a..0w..=......./...EA.?0=1.0...co.openvine.app..\\n.1\\\". ......[.....N..<............,A.u..T\\\". ..F#...H..i,|.._...w..........!.0....1....................1...........w.....>......@L0J. .\\\\.......O.%.Zx3i..2........*......\\n... ....bU.g.. ..02.X.r.u.g..x.J:8....A....q...B.....m..N....5&...O....5&.\\n    Signature Algorithm: ecdsa-with-SHA256\\n         30:44:02:20:53:63:76:cf:0a:67:dc:92:d7:a5:d8:0a:62:7b:\\n         3a:6d:9f:fd:f0:a3:a4:c2:23:40:51:39:ae:a6:63:0d:99:95:\\n         02:20:3e:11:4e:8d:1b:c5:b4:22:69:ec:85:fe:1e:80:4c:a5:\\n         bb:34:6f:5a:25:e1:38:13:bd:af:c4:33:cb:5b:bf:2c\\n\\n\\nCertificate:\\n    Data:\\n        Version: 3 (0x2)\\n        Serial Number:\\n            5f:87:cc:ed:30:b5:9a:7c:f9:63:27:fe:53:ab:bd:3f\\n    Signature Algorithm: ecdsa-with-SHA256\\n        Issuer: O=Google LLC, CN=Droid CA3\\n        Validity\\n            Not Before: May 30 00:49:36 2026 GMT\\n            Not After : Jun 13 22:12:02 2026 GMT\\n        Subject: O=TEE, CN=5f87cced30b59a7cf96327fe53abbd3f\\n        Subject Public Key Info:\\n            Public Key Algorithm: id-ecPublicKey\\n                Public-Key: (P-256)\\n                pub:\\n                    04:ca:8d:0c:c3:09:6a:5a:17:64:66:6d:a6:a1:f5:\\n                    ea:0a:fe:35:42:84:27:8d:fc:b2:c6:d9:e9:bc:8e:\\n                    4a:af:6e:28:b6:ef:40:48:95:01:59:c3:4b:ac:5a:\\n                    0f:f8:e9:82:96:cd:e9:f4:a6:43:00:58:ec:1e:80:\\n                    c6:32:58:5a:46\\n        X509v3 extensions:\\n            X509v3 Subject Key Identifier: \\n                E5:11:65:47:21:5A:DC:DB:AC:17:3C:9E:6B:11:3E:B8:17:08:65:C1\\n            X509v3 Authority Key Identifier: \\n                keyid:ED:6D:98:53:0A:D7:24:16:EE:37:F7:C5:D4:49:80:22:02:6B:42:ED\\n\\n            X509v3 Basic Constraints: critical\\n                CA:TRUE\\n            X509v3 Key Usage: critical\\n                Certificate Sign\\n            1.3.6.1.4.1.11129.2.1.30: \\n                ...@.fGoogle\\n    Signature Algorithm: ecdsa-with-SHA256\\n         30:45:02:21:00:be:2c:af:dc:46:7c:50:a7:ed:49:96:15:86:\\n         1a:41:dc:d4:5e:b9:32:25:9e:41:35:fb:dc:74:20:7b:b9:fc:\\n         a4:02:20:16:a2:e9:3e:d9:f1:0c:38:de:ec:97:b7:a7:ca:bb:\\n         8d:06:e1:c1:82:fa:49:ab:42:dc:17:f8:3a:ca:a6:00:64\\n\\n\\nCertificate:\\n    Data:\\n        Version: 3 (0x2)\\n        Serial Number:\\n            85:83:e6:66:12:81:61:26:e1:d4:4a:db:0a:af:59:f4:5d:44:1c\\n    Signature Algorithm: ecdsa-with-SHA384\\n        Issuer: O=Google LLC, CN=Droid CA2\\n        Validity\\n            Not Before: May 27 19:42:37 2026 GMT\\n            Not After : Aug  5 19:42:36 2026 GMT\\n        Subject: O=Google LLC, CN=Droid CA3\\n        Subject Public Key Info:\\n            Public Key Algorithm: id-ecPublicKey\\n                Public-Key: (P-256)\\n                pub:\\n                    04:75:a7:7e:7b:6e:f2:7d:c0:3c:6a:65:92:ee:48:\\n                    74:03:e9:cb:43:d6:74:2c:0c:8e:86:a0:b8:6c:bd:\\n                    5b:0c:2a:d3:4d:01:cd:e7:ec:dc:4a:5e:67:fd:4a:\\n                    a1:27:59:9e:71:d8:86:41:90:f8:9b:6b:34:7f:59:\\n                    69:ae:d2:3b:69\\n        X509v3 extensions:\\n            X509v3 Key Usage: critical\\n                Certificate Sign\\n            X509v3 Basic Constraints: critical\\n                CA:TRUE\\n            X509v3 Subject Key Identifier: \\n                ED:6D:98:53:0A:D7:24:16:EE:37:F7:C5:D4:49:80:22:02:6B:42:ED\\n            X509v3 Authority Key Identifier: \\n                keyid:45:20:32:3E:1F:A6:F9:8F:1C:D5:C3:47:2E:D4:7A:50:FE:3B:A8:E0\\n\\n            Authority Information Access: \\n                CA Issuers - URI:http://privateca-content-69e35229-0000-28ff-b506-14c14ef5ac58.storage.googleapis.com/01d1d1bcb73268579a5f/ca.crt\\n\\n            X509v3 CRL Distribution Points: \\n\\n                Full Name:\\n                  URI:http://privateca-content-69e35229-0000-28ff-b506-14c14ef5ac58.storage.googleapis.com/01d1d1bcb73268579a5f/crl.crl\\n\\n    Signature Algorithm: ecdsa-with-SHA384\\n         30:64:02:30:01:30:d4:33:ac:c1:c6:66:90:ff:2f:94:36:0f:\\n         2d:8f:39:50:3f:31:4a:b4:2e:d6:6b:16:4a:66:94:e0:74:c8:\\n         63:f2:ec:d4:05:11:1d:6a:ee:9b:7b:8f:7e:f3:a9:7d:02:30:\\n         21:12:ce:9b:c7:9c:d5:19:6c:df:de:1a:bf:a7:a2:87:c5:8f:\\n         10:c8:76:bd:c1:f7:3f:97:a6:32:80:f1:c3:9d:d0:be:2f:f5:\\n         06:ad:63:a1:32:ca:ce:fd:2d:ee:20:6d\\n\\n\\nCertificate:\\n    Data:\\n        Version: 3 (0x2)\\n        Serial Number:\\n            b1:84:cb:05:ec:50:fd:c9:85:f0:ec:53:29:7c:f8:23\\n    Signature Algorithm: ecdsa-with-SHA384\\n        Issuer: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\\n        Validity\\n            Not Before: Feb  9 19:57:10 2026 GMT\\n            Not After : Feb  8 19:57:10 2029 GMT\\n        Subject: O=Google LLC, CN=Droid CA2\\n        Subject Public Key Info:\\n            Public Key Algorithm: id-ecPublicKey\\n                Public-Key: (P-384)\\n                pub:\\n                    04:f5:f7:eb:51:02:59:b0:b9:ab:95:c9:1a:e0:1e:\\n                    ac:a4:93:29:9a:12:43:92:d4:86:12:a1:70:10:c8:\\n                    14:6f:50:d1:27:63:91:46:aa:68:b8:e1:d3:96:72:\\n                    a3:31:bb:4b:88:6c:1d:e2:9f:94:c3:dc:6b:11:d4:\\n                    d0:66:8b:77:ff:fe:62:34:6a:20:11:6c:1b:5d:3f:\\n                    76:1a:21:f7:fc:cb:2d:3b:e8:d6:3d:74:f3:27:06:\\n                    20:8c:23:08:d1:47:60\\n        X509v3 extensions:\\n            X509v3 CRL Distribution Points: \\n\\n                Full Name:\\n                  URI:https://android.googleapis.com/attestation/key_ca1.crl\\n\\n            X509v3 Subject Key Identifier: \\n                45:20:32:3E:1F:A6:F9:8F:1C:D5:C3:47:2E:D4:7A:50:FE:3B:A8:E0\\n            X509v3 Key Usage: critical\\n                Certificate Sign, CRL Sign\\n            X509v3 Basic Constraints: critical\\n                CA:TRUE\\n            X509v3 Authority Key Identifier: \\n                keyid:52:32:BB:2C:FB:46:43:9B:DC:D6:81:A9:0E:65:66:E0:34:41:EA:40\\n\\n    Signature Algorithm: ecdsa-with-SHA384\\n         30:65:02:30:5f:39:79:98:d7:e4:82:71:3f:e8:58:bd:7b:02:\\n         e5:52:ee:ea:31:31:7b:2c:2e:4b:23:0a:11:d3:f9:58:53:32:\\n         95:ae:f4:9e:36:c7:71:b6:d2:11:d5:19:38:fe:dd:92:02:31:\\n         00:c1:61:98:dd:ef:eb:df:bb:22:d5:09:99:13:5f:bc:25:be:\\n         37:11:26:3b:eb:11:6c:b1:be:46:44:e6:f9:6a:f1:cd:e5:c0:\\n         7f:49:c8:d0:4f:dc:e7:93:77:7a:3c:20:9b\\n\\n\\nCertificate:\\n    Data:\\n        Version: 3 (0x2)\\n        Serial Number:\\n            84:a9:d0:29:7b:0e:b5:8a:e7:ff:0e:80:de:76:06:05\\n    Signature Algorithm: ecdsa-with-SHA384\\n        Issuer: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\\n        Validity\\n            Not Before: Jul 17 22:32:18 2025 GMT\\n            Not After : Jul 15 22:32:18 2035 GMT\\n        Subject: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\\n        Subject Public Key Info:\\n            Public Key Algorithm: id-ecPublicKey\\n                Public-Key: (P-384)\\n                pub:\\n                    04:23:da:23:71:4e:df:3e:5b:05:0a:3c:72:e8:84:\\n                    6a:ce:07:8e:a0:ad:1b:f9:8b:15:f4:53:d0:cb:08:\\n                    b2:c3:c1:10:45:39:09:f6:ed:ea:c1:f9:c8:e0:31:\\n                    a8:48:b9:41:a8:29:53:5c:97:e0:7c:27:19:be:ce:\\n                    b4:16:29:0d:30:79:ee:e1:f9:11:cc:e6:df:80:39:\\n                    14:d8:a3:57:7b:34:fd:fd:14:3e:5e:f3:6c:97:13:\\n                    c7:ac:70:a8:c2:11:ab\\n        X509v3 extensions:\\n            X509v3 Basic Constraints: critical\\n                CA:TRUE\\n            X509v3 Key Usage: critical\\n                Certificate Sign, CRL Sign\\n            X509v3 Subject Key Identifier: \\n                52:32:BB:2C:FB:46:43:9B:DC:D6:81:A9:0E:65:66:E0:34:41:EA:40\\n    Signature Algorithm: ecdsa-with-SHA384\\n         30:65:02:30:44:df:8c:f3:bf:1f:0a:91:79:1d:82:4b:ba:74:\\n         65:6a:03:fc:b1:ec:ea:10:e2:e3:6d:a8:a6:27:c7:11:46:98:\\n         2f:1c:06:95:3f:52:2d:d8:e4:56:9c:f4:51:43:91:e7:02:31:\\n         00:8a:06:cb:11:8a:44:75:53:a6:aa:46:44:58:89:b5:01:0e:\\n         39:3a:7f:fa:cd:46:73:17:98:b9:1d:b3:87:ff:34:95:0c:ae:\\n         f6:f0:05:0a:3e:84:e0:05:dc:fa:8b:26:46\\n\\n\\n\"}"],["device_attestation","Certificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number: 1 (0x1)\n    Signature Algorithm: ecdsa-with-SHA256\n        Issuer: O=TEE, CN=5f87cced30b59a7cf96327fe53abbd3f\n        Validity\n            Not Before: Jan  1 00:00:00 1970 GMT\n            Not After : Jan  1 00:00:00 2048 GMT\n        Subject: CN=Android Keystore Key\n        Subject Public Key Info:\n            Public Key Algorithm: id-ecPublicKey\n                Public-Key: (P-256)\n                pub:\n                    04:ed:23:83:f4:28:9d:97:7a:1f:97:51:33:e5:3b:\n                    63:e1:c6:87:70:b4:48:47:fe:b5:34:b1:f9:18:37:\n                    05:de:bd:a3:9d:96:d7:0a:ac:37:bc:a0:97:8c:47:\n                    02:98:cf:f3:b1:c3:6f:9a:49:f0:40:17:d1:9e:ce:\n                    bf:ff:b9:71:e1\n        X509v3 extensions:\n            X509v3 Key Usage: critical\n                Digital Signature\n            1.3.6.1.4.1.11129.2.1.17: \n                0..r....\n......\n...@e0dc8ce55fd567aae76a65266805fa80f164cebf7b5b99c536e286b5182c331a..0w..=......./...EA.?0=1.0...co.openvine.app..\n.1\". ......[.....N..<............,A.u..T\". ..F#...H..i,|.._...w..........!.0....1....................1...........w.....>......@L0J. .\\.......O.%.Zx3i..2........*......\n... ....bU.g.. ..02.X.r.u.g..x.J:8....A....q...B.....m..N....5&...O....5&.\n    Signature Algorithm: ecdsa-with-SHA256\n         30:44:02:20:53:63:76:cf:0a:67:dc:92:d7:a5:d8:0a:62:7b:\n         3a:6d:9f:fd:f0:a3:a4:c2:23:40:51:39:ae:a6:63:0d:99:95:\n         02:20:3e:11:4e:8d:1b:c5:b4:22:69:ec:85:fe:1e:80:4c:a5:\n         bb:34:6f:5a:25:e1:38:13:bd:af:c4:33:cb:5b:bf:2c\n\n\nCertificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number:\n            5f:87:cc:ed:30:b5:9a:7c:f9:63:27:fe:53:ab:bd:3f\n    Signature Algorithm: ecdsa-with-SHA256\n        Issuer: O=Google LLC, CN=Droid CA3\n        Validity\n            Not Before: May 30 00:49:36 2026 GMT\n            Not After : Jun 13 22:12:02 2026 GMT\n        Subject: O=TEE, CN=5f87cced30b59a7cf96327fe53abbd3f\n        Subject Public Key Info:\n            Public Key Algorithm: id-ecPublicKey\n                Public-Key: (P-256)\n                pub:\n                    04:ca:8d:0c:c3:09:6a:5a:17:64:66:6d:a6:a1:f5:\n                    ea:0a:fe:35:42:84:27:8d:fc:b2:c6:d9:e9:bc:8e:\n                    4a:af:6e:28:b6:ef:40:48:95:01:59:c3:4b:ac:5a:\n                    0f:f8:e9:82:96:cd:e9:f4:a6:43:00:58:ec:1e:80:\n                    c6:32:58:5a:46\n        X509v3 extensions:\n            X509v3 Subject Key Identifier: \n                E5:11:65:47:21:5A:DC:DB:AC:17:3C:9E:6B:11:3E:B8:17:08:65:C1\n            X509v3 Authority Key Identifier: \n                keyid:ED:6D:98:53:0A:D7:24:16:EE:37:F7:C5:D4:49:80:22:02:6B:42:ED\n\n            X509v3 Basic Constraints: critical\n                CA:TRUE\n            X509v3 Key Usage: critical\n                Certificate Sign\n            1.3.6.1.4.1.11129.2.1.30: \n                ...@.fGoogle\n    Signature Algorithm: ecdsa-with-SHA256\n         30:45:02:21:00:be:2c:af:dc:46:7c:50:a7:ed:49:96:15:86:\n         1a:41:dc:d4:5e:b9:32:25:9e:41:35:fb:dc:74:20:7b:b9:fc:\n         a4:02:20:16:a2:e9:3e:d9:f1:0c:38:de:ec:97:b7:a7:ca:bb:\n         8d:06:e1:c1:82:fa:49:ab:42:dc:17:f8:3a:ca:a6:00:64\n\n\nCertificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number:\n            85:83:e6:66:12:81:61:26:e1:d4:4a:db:0a:af:59:f4:5d:44:1c\n    Signature Algorithm: ecdsa-with-SHA384\n        Issuer: O=Google LLC, CN=Droid CA2\n        Validity\n            Not Before: May 27 19:42:37 2026 GMT\n            Not After : Aug  5 19:42:36 2026 GMT\n        Subject: O=Google LLC, CN=Droid CA3\n        Subject Public Key Info:\n            Public Key Algorithm: id-ecPublicKey\n                Public-Key: (P-256)\n                pub:\n                    04:75:a7:7e:7b:6e:f2:7d:c0:3c:6a:65:92:ee:48:\n                    74:03:e9:cb:43:d6:74:2c:0c:8e:86:a0:b8:6c:bd:\n                    5b:0c:2a:d3:4d:01:cd:e7:ec:dc:4a:5e:67:fd:4a:\n                    a1:27:59:9e:71:d8:86:41:90:f8:9b:6b:34:7f:59:\n                    69:ae:d2:3b:69\n        X509v3 extensions:\n            X509v3 Key Usage: critical\n                Certificate Sign\n            X509v3 Basic Constraints: critical\n                CA:TRUE\n            X509v3 Subject Key Identifier: \n                ED:6D:98:53:0A:D7:24:16:EE:37:F7:C5:D4:49:80:22:02:6B:42:ED\n            X509v3 Authority Key Identifier: \n                keyid:45:20:32:3E:1F:A6:F9:8F:1C:D5:C3:47:2E:D4:7A:50:FE:3B:A8:E0\n\n            Authority Information Access: \n                CA Issuers - URI:http://privateca-content-69e35229-0000-28ff-b506-14c14ef5ac58.storage.googleapis.com/01d1d1bcb73268579a5f/ca.crt\n\n            X509v3 CRL Distribution Points: \n\n                Full Name:\n                  URI:http://privateca-content-69e35229-0000-28ff-b506-14c14ef5ac58.storage.googleapis.com/01d1d1bcb73268579a5f/crl.crl\n\n    Signature Algorithm: ecdsa-with-SHA384\n         30:64:02:30:01:30:d4:33:ac:c1:c6:66:90:ff:2f:94:36:0f:\n         2d:8f:39:50:3f:31:4a:b4:2e:d6:6b:16:4a:66:94:e0:74:c8:\n         63:f2:ec:d4:05:11:1d:6a:ee:9b:7b:8f:7e:f3:a9:7d:02:30:\n         21:12:ce:9b:c7:9c:d5:19:6c:df:de:1a:bf:a7:a2:87:c5:8f:\n         10:c8:76:bd:c1:f7:3f:97:a6:32:80:f1:c3:9d:d0:be:2f:f5:\n         06:ad:63:a1:32:ca:ce:fd:2d:ee:20:6d\n\n\nCertificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number:\n            b1:84:cb:05:ec:50:fd:c9:85:f0:ec:53:29:7c:f8:23\n    Signature Algorithm: ecdsa-with-SHA384\n        Issuer: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\n        Validity\n            Not Before: Feb  9 19:57:10 2026 GMT\n            Not After : Feb  8 19:57:10 2029 GMT\n        Subject: O=Google LLC, CN=Droid CA2\n        Subject Public Key Info:\n            Public Key Algorithm: id-ecPublicKey\n                Public-Key: (P-384)\n                pub:\n                    04:f5:f7:eb:51:02:59:b0:b9:ab:95:c9:1a:e0:1e:\n                    ac:a4:93:29:9a:12:43:92:d4:86:12:a1:70:10:c8:\n                    14:6f:50:d1:27:63:91:46:aa:68:b8:e1:d3:96:72:\n                    a3:31:bb:4b:88:6c:1d:e2:9f:94:c3:dc:6b:11:d4:\n                    d0:66:8b:77:ff:fe:62:34:6a:20:11:6c:1b:5d:3f:\n                    76:1a:21:f7:fc:cb:2d:3b:e8:d6:3d:74:f3:27:06:\n                    20:8c:23:08:d1:47:60\n        X509v3 extensions:\n            X509v3 CRL Distribution Points: \n\n                Full Name:\n                  URI:https://android.googleapis.com/attestation/key_ca1.crl\n\n            X509v3 Subject Key Identifier: \n                45:20:32:3E:1F:A6:F9:8F:1C:D5:C3:47:2E:D4:7A:50:FE:3B:A8:E0\n            X509v3 Key Usage: critical\n                Certificate Sign, CRL Sign\n            X509v3 Basic Constraints: critical\n                CA:TRUE\n            X509v3 Authority Key Identifier: \n                keyid:52:32:BB:2C:FB:46:43:9B:DC:D6:81:A9:0E:65:66:E0:34:41:EA:40\n\n    Signature Algorithm: ecdsa-with-SHA384\n         30:65:02:30:5f:39:79:98:d7:e4:82:71:3f:e8:58:bd:7b:02:\n         e5:52:ee:ea:31:31:7b:2c:2e:4b:23:0a:11:d3:f9:58:53:32:\n         95:ae:f4:9e:36:c7:71:b6:d2:11:d5:19:38:fe:dd:92:02:31:\n         00:c1:61:98:dd:ef:eb:df:bb:22:d5:09:99:13:5f:bc:25:be:\n         37:11:26:3b:eb:11:6c:b1:be:46:44:e6:f9:6a:f1:cd:e5:c0:\n         7f:49:c8:d0:4f:dc:e7:93:77:7a:3c:20:9b\n\n\nCertificate:\n    Data:\n        Version: 3 (0x2)\n        Serial Number:\n            84:a9:d0:29:7b:0e:b5:8a:e7:ff:0e:80:de:76:06:05\n    Signature Algorithm: ecdsa-with-SHA384\n        Issuer: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\n        Validity\n            Not Before: Jul 17 22:32:18 2025 GMT\n            Not After : Jul 15 22:32:18 2035 GMT\n        Subject: CN=Key Attestation CA1, OU=Android, O=Google LLC, C=US\n        Subject Public Key Info:\n            Public Key Algorithm: id-ecPublicKey\n                Public-Key: (P-384)\n                pub:\n                    04:23:da:23:71:4e:df:3e:5b:05:0a:3c:72:e8:84:\n                    6a:ce:07:8e:a0:ad:1b:f9:8b:15:f4:53:d0:cb:08:\n                    b2:c3:c1:10:45:39:09:f6:ed:ea:c1:f9:c8:e0:31:\n                    a8:48:b9:41:a8:29:53:5c:97:e0:7c:27:19:be:ce:\n                    b4:16:29:0d:30:79:ee:e1:f9:11:cc:e6:df:80:39:\n                    14:d8:a3:57:7b:34:fd:fd:14:3e:5e:f3:6c:97:13:\n                    c7:ac:70:a8:c2:11:ab\n        X509v3 extensions:\n            X509v3 Basic Constraints: critical\n                CA:TRUE\n            X509v3 Key Usage: critical\n                Certificate Sign, CRL Sign\n            X509v3 Subject Key Identifier: \n                52:32:BB:2C:FB:46:43:9B:DC:D6:81:A9:0E:65:66:E0:34:41:EA:40\n    Signature Algorithm: ecdsa-with-SHA384\n         30:65:02:30:44:df:8c:f3:bf:1f:0a:91:79:1d:82:4b:ba:74:\n         65:6a:03:fc:b1:ec:ea:10:e2:e3:6d:a8:a6:27:c7:11:46:98:\n         2f:1c:06:95:3f:52:2d:d8:e4:56:9c:f4:51:43:91:e7:02:31:\n         00:8a:06:cb:11:8a:44:75:53:a6:aa:46:44:58:89:b5:01:0e:\n         39:3a:7f:fa:cd:46:73:17:98:b9:1d:b3:87:ff:34:95:0c:ae:\n         f6:f0:05:0a:3e:84:e0:05:dc:fa:8b:26:46\n\n\n"]],"sig":"d1dac892c809851b289db06ffbf228d83fced9490ba1fce44179f523ec9a2b2aed7aaaa7fe49afd4de4b1cd50a10db39b0be9ef5db0bf753a9475265149a76ab","created_at":1780428000,"pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"}"###)

    PreviewContainer({ pe in
        
    }) {
        PreviewApp {
            GeometryReader { geo in
                let posts = [nrPost00, nrPost0, nrPost1, nrPost2, nrPost3, nrPost4, nrPost5]
                if #available(iOS 17.0, *) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(posts, id: \.id) { post in
                                PostRowDeletable(nrPost: post, theme: theme)
                                    .environment(\.availableHeight, geo.size.height)
                                    .environment(\.availableWidth, geo.size.width)
                                    .frame(height: geo.size.height)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                } else {
                    ScrollView {
                        ForEach(posts, id: \.id) { post in
                            PostOrThread(nrPost: post, theme: theme)
                                .environment(\.availableHeight, geo.size.height)
                                .environment(\.availableWidth, geo.size.width)
                        }
                    }
                }
            }
        }
        .environmentObject(VideoPostPlaybackCoordinator())
    }
}

