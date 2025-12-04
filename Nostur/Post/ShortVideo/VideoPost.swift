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
    
    func reportVisibility(postID: String, visibility: CGFloat) {
        guard visibility > 0.2 else { return }
        visibilities[postID] = visibility
        updateMostVisible()
    }
    func removeVisibility(postID: String) {
        visibilities.removeValue(forKey: postID)
        updateMostVisible()
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
    @EnvironmentObject private var coordinator: VideoPostPlaybackCoordinator
    
    public let nrPost: NRPost
    public var isDetail: Bool = false
    public var isEmbedded: Bool = false
    public var isVisible: Bool = true
    public let theme: Theme
    
    @State private var isPlaying = false
    
    private var postID: String { nrPost.id }
    
    @State var canPlay = true
    
    private var videoWidth: CGFloat {
        if nxViewingContext.contains(.postParent) {
            return availableWidth - 20
        }
        return availableWidth
    }
    
    var body: some View {
        VideoPostLayout(nrPost: nrPost, theme: theme) {
            if let videoURL = nrPost.eventUrl {
                if #available(iOS 16.0, *) {
                    ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying)
                        .frame(width: videoWidth, height: min((videoWidth*3), availableHeight))
                        .background(Color.black)
                        .frame(width: videoWidth, height: availableHeight)
                        .onTapGesture { isPlaying.toggle() }
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
                                    isPlaying = (coordinator.mostVisiblePostID == postID)
                                }
                                .onDisappear {
                                    canPlay = false
                                    //guard isVisible else { return }
                                    coordinator.removeVisibility(postID: postID)
                                    isPlaying = false
                                }
                                .onChange(of: coordinator.mostVisiblePostID) { newValue in
                                    guard canPlay && isVisible else { return }
                                    isPlaying = (coordinator.mostVisiblePostID == postID)
                                }
                                
                            }
                            else { $0 }
                        }
                } else {
                    GeometryReader { geo in
                        ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying)
                            .frame(width: videoWidth, height: min((videoWidth*3), availableHeight))
                            .background(Color.black)
                            .frame(width: videoWidth, height: availableHeight)
                            .onTapGesture { isPlaying.toggle() }
                            .modifier {
                                if !isDetail && !nxViewingContext.contains(.preview) {
                                    $0.onAppear {
                                        canPlay = true
                                        guard isVisible else { return }
                                        updateVisibilityPreiOS16(geo: geo)
                                        isPlaying = (coordinator.mostVisiblePostID == postID)
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
                                    .onChange(of: coordinator.mostVisiblePostID) { newValue in
                                        guard canPlay && isVisible else { return }
                                        isPlaying = (coordinator.mostVisiblePostID == postID)
                                    }
                                }
                                else { $0 }
                            }
                    }
                    .frame(width: videoWidth, height: availableHeight)
                }
            }
        }
        .onValueChange(isVisible) { wasVisible, isVisibleNow in
            // When changing feed, don't continue playing
            guard isPlaying && !isVisibleNow else { return }
            isPlaying = false
        }
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

    PreviewContainer({ pe in
        
    }) {
        PreviewApp {
            GeometryReader { geo in
                let posts = [nrPost0, nrPost1, nrPost2, nrPost3, nrPost4, nrPost5]
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

