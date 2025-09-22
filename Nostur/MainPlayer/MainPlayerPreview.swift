//
//  MainPlayerPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//


import SwiftUI
import NavigationBackport

@available(iOS 18.0, *)
#Preview("Integrated media player bar") {
    @Previewable @State var offset: CGFloat = 69.0
    @Previewable @State var enableLiveEvents: Bool = true
    @Previewable @ObservedObject var apm: AnyPlayerModel = .shared
//    @Previewable @ObservedObject var ss: SettingsStore = .shared
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // live event
            ###"["EVENT","LIVEEVENT-LIVE2",{"kind":30311,"id":"03082afe5364b086293a60c3fc982d5265083af66b726cecd0978d3f0d5be1e0","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1720098927,"tags":[["d","569180c5-adec-40a6-a41b-513f39ded13a"],["title",""],["summary","Send a zap to flash the lamp! There is a ~15 sec between your zap and the stream."],["image","https://dvr.zap.stream/zap-stream-dvr/569180c5-adec-40a6-a41b-513f39ded13a/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277007695\u0026Signature=Zqbwvwam70uT9UKRBW0fmHHzLrI%3D"],["status","live"],["p","9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1719911364"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/569180c5-adec-40a6-a41b-513f39ded13a.m3u8"],["current_participants","0"],["t","zaplamp"],["t","lnbits"],["t","zapathon"],["t","internal:art"],["goal","66d73e8f3de742e70e3f5b1c30ff2a028fae0d4f1efad53089172e5c05563579"]],"content":"","sig":"4321619ff3aa63387aefc7403baea01317a7c408cfa2547546046e354e4a765af886ee9c509f1ca6043be7cf01bdff696cf521261316c5261a2a42eed87e5289"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.parseMessages([
            ###"["EVENT","e",{"kind":30311,"id":"75558b5933f0b7002df3dbe5356df2ab1144f8c0595e8d60282382a2007d5ed7","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1721669595,"tags":[["d","82d27633-1dd1-4b38-8f9d-f6ab9b31fc83"],["title","Fiatjaf \u0026 utxo play dominion"],["summary","Come watch this very exciting game"],["image","https://dvr.zap.stream/zap-stream-dvr/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33278578238\u0026Signature=X4Jo1oAm5pIg0YZ40CobUUdpD2A%3D"],["status","ended"],["p","e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1721664799"],["service","https://api.zap.stream/api/nostr"],["recording","https://data.zap.stream/recording/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83.m3u8"],["ends","1721669595"]],"content":"","sig":"3f03a0de44dd2eec8dd045d5dd2242d1558f2af7719955e9ceb300c4ee14f26e4a170b13db923fb313bf4fd5d2c60be344f7901ea3ef5dd7f0fcb8df908b8b21"}]"###,
            ###"["EVENT","LIVE",{"content":"","created_at":1718076971,"id":"1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2","kind":30311,"pubkey":"8a0969377e9abfe215e99f02e1789437892526b1d1e0b1ca4ed7cbf88b1cc421","sig":"2eb76ceda6c1345465998fe14cf53da308880fd1cf2f70e6c0d6e248d1a903105301f99f04c8e230272aaf0c8ee5a35c7c2b03cc63e64e62e88b7b55111f3920","tags":[["d","1718063831277"],["title","Corny Chat News"],["summary","Weekly news roundup providing a summary of the weeks headlines and topical discussion regarding Nostr, Lightning, Bitcoin, Geopolitics and Clown World, Humor and more."],["image","https://image.nostr.build/ea30115d83b1d3c303095a0a3349514ca2a88e12b9c5dd7fd92e984502be55f0.jpg"],["service","https://cornychat.com/cornychatnews"],["streaming","https://cornychat.com/cornychatnews"],["starts","1718063831"],["ends","1718080571"],["status","live"],["current_participants","7"],["t","talk"],["t","talk show"],["L","com.cornychat"],["l","cornychat.com","com.cornychat"],["l","audiospace","com.cornychat"],["r","https://cornychat.com/cornychatnews"],["p","50809a53fef95904513a840d4082a92b45cd5f1b9e436d9d2b92a89ce091f164","","Participant"],["p","7cc328a08ddb2afdf9f9be77beff4c83489ff979721827d628a542f32a247c0e","","Participant"],["p","21b419102da8fc0ba90484aec934bf55b7abcf75eedb39124e8d75e491f41a5e","","Room Owner"],["p","52387c6b99cc42aac51916b08b7b51d2baddfc19f2ba08d82a48432849dbdfb2","","Participant"],["p","50de492cfe5472450df1a0176fdf6d915e97cb5d9f8d3eccef7d25ff0a8871de","","Speaker"],["p","9322bd922f20c6fcd9e913454727b3bbc2d096be4811971055a826dda3d4cb0b","","Participant"],["p","cc76679480a4504b963a3809cba60b458ebf068c62713621dda94b527860447d","","Participant"]]}]"###
        ])
        pe.loadNoDBChats()
    }) {
        TabView {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Color.blue.opacity(0.2)
                    VStack {
                        
                        if apm.viewMode == .audioOnlyBar {
                            // Spacer for OverlayVideo here
                        }
                        else if enableLiveEvents {
                            LiveEventsBanner(showLiveEventsBanner: .constant(true))
                                .animation(.easeIn, value: enableLiveEvents)
                                .opacity(apm.viewMode == .audioOnlyBar ? 0 : 1.0)
                        }
                        
                        HStack {
                            Button("Landscape") {
                                Task {
                                    await AnyPlayerModel
                                        .shared
                                        .loadVideo(
                                            url: "https://static.vecteezy.com/system/resources/previews/016/465/804/mp4/silhouettes-flock-of-seagulls-over-the-sea-during-amazing-sky-video.mp4",
            //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                            availableViewModes: [.fullscreen, .overlay])
                                }
                            }
                            
                            Button("Stream") {
                                Task {
                                    await AnyPlayerModel
                                        .shared
                                        .loadVideo(
                                            url: "https://data.zap.stream/stream/537a365c-f1ec-44ac-af10-22d14a7319fb.m3u8",
                                            availableViewModes: [.fullscreen, .overlay, .detailstream, .audioOnlyBar])
//                                            availableViewModes: [.audioOnlyBar])
//                                            availableViewModes: [.detailstream, .overlay, .audioOnlyPill])
                                }
                            }
                            
                            Button("Portrait") {
                                Task {
                                    await AnyPlayerModel
                                        .shared
                                        .loadVideo(
                                            url: "https://m.primal.net/OErQ.mov",
            //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                            availableViewModes: [.fullscreen, .overlay])
                                }
                            }
                            
                            Button("Other") {
                                Task {
                                    await AnyPlayerModel
                                        .shared
                                        .loadVideo(
                                            url: "https://m.primal.net/OEzS.mp4",
            //                                availableViewModes: [.fullscreen, .overlay, .detailstream])
                                            availableViewModes: [.fullscreen, .overlay])
                                }
                            }
                            
                            Button("Close") {
                                AnyPlayerModel.shared.close()
                            }
                        }
                        
                        Text("Tab 1")
                    }
                }
                    .tabItem { Label("", systemImage: "house") }
                    .tag("Main")
                    .preference(key: TabBarHeightKey.self, value: geometry.size.height)
            }
            
            Text("Tab 2")
                .tabItem { Label("", systemImage: "bookmark") }
                .tag("Bookmarks")
            
            Text("Tab 3")
                .tabItem { Label("", systemImage: "magnifyingglass") }
                .tag("Search")
            
            Text("Tab 4")
                .tabItem { Label("", systemImage: "bell.fill") }
                .tag("Notifications")
                .badge(2)
            
            Text("Tab 5")
                .tabItem { Label("", systemImage: "envelope.fill") }
                .tag("Messages")
                .badge(1)
        }
        .overlay(alignment: .center) {
            OverlayPlayer()
                .edgesIgnoringSafeArea(.bottom)
        }
        .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight in
            print("Tab Bar Height: \(UIScreen.main.bounds.height - tabBarHeight)")
        }
    }
}

struct TabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

