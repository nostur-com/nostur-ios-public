//
//  LiveNowBanner.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import SwiftUI
import NavigationBackport

struct LiveEventsBanner: View {
    @Binding var showLiveEventsBanner: Bool
    @AppStorage("enable_live_events") private var enableLiveEvents: Bool = true
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var npn: NewPostNotifier
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var apm: AnyPlayerModel = .shared
    @ObservedObject private var liveEventsModel: LiveEventsModel = .shared
    @ObservedObject private var liveKitVoiceSession: LiveKitVoiceSession = .shared
    @State private var didLoad = false
    @State private var showCreateNestsSheetWithAccount: CloudAccount? = nil
    
    var body: some View {
        if enableLiveEvents && apm.viewMode != .audioOnlyBar  {
            ScrollView(.horizontal, showsIndicators: false) {
                if !liveEventsModel.nrLiveEvents.isEmpty {
                    HStack {
                        ForEach(liveEventsModel.nrLiveEvents) { nrLiveEvent in
                            LiveEventCapsule(liveEvent: nrLiveEvent, onRemove: remove)
                                .frame(maxWidth: DIMENSIONS.availableNoteRowImageWidth(availableWidth))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .onAppear {
                        guard !showLiveEventsBanner else { return }
                        showLiveEventsBanner = true
                    }
                    .onDisappear {
                        guard showLiveEventsBanner else { return }
                        showLiveEventsBanner = false
                    }
                }
                else {
                    EmptyView()
                }
            }
            .scrollTargetBehaviorViewAligned()
            .safeAreaPadding()
            .frame(height: 50)
            .animation(.interactiveSpring, value: liveEventsModel.nrLiveEvents)
            .animation(.easeIn, value: enableLiveEvents)
            .onAppear {
                guard !didLoad else { return }
                liveEventsModel.load()
                didLoad = true
            }
            .onReceive(receiveNotification(.showCreateNestsSheet)) { notification in
                let acount = notification.object as! CloudAccount
                showCreateNestsSheetWithAccount = acount
            }
            .onReceive(receiveNotification(.hideCreateNestsSheet)) { _ in
                showCreateNestsSheetWithAccount = nil
            }
            .fullScreenCover(item: $showCreateNestsSheetWithAccount, content: { account in
                NBNavigationStack {
                    CreateNest(account: account)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", systemImage: "xmark") { showCreateNestsSheetWithAccount = nil }
                            }
                        }
                        .padding()
                }
            })
            .fullScreenCover(item: $liveKitVoiceSession.visibleNest) { visibleNest in
                NRNavigationStack {
                    LiveEventDetail(liveEvent: visibleNest)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                if visibleNest == LiveKitVoiceSession.shared.activeNest, case .connected = liveKitVoiceSession.state {
                                    Button("Leave", systemImage: "xmark") {
                                        LiveKitVoiceSession.shared.activeNest = nil
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                                else {
                                    Button("Close", systemImage: "xmark") {
                                        LiveKitVoiceSession.shared.activeNest = nil
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                            }
                            
                            ToolbarItem(placement: .primaryAction) {
                                if visibleNest == LiveKitVoiceSession.shared.activeNest, case .connected = liveKitVoiceSession.state {
                                    Button("Minimize", systemImage: "rectangle.portrait.topthird.inset.filled") {
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                            }
                        }
                        .presentationBackgroundCompat(theme.listBackground)
                }
                .environmentObject(la)
            }
            
        }
    }
    
    private func remove(_ aTag: String) {
        liveEventsModel.dismissedLiveEvents.insert(aTag)
    }
}

#Preview("Live banner") {
    PreviewContainer({ pe in
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // live event
            ###"["EVENT","LIVEEVENT-LIVE2",{"kind":30311,"id":"03082afe5364b086293a60c3fc982d5265083af66b726cecd0978d3f0d5be1e0","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720098927,"tags":[["d","569180c5-adec-40a6-a41b-513f39ded13a"],["title",""],["summary","Send a zap to flash the lamp! There is a ~15 sec between your zap and the stream."],["image","https://dvr.zap.stream/zap-stream-dvr/569180c5-adec-40a6-a41b-513f39ded13a/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277007695\u0026Signature=Zqbwvwam70uT9UKRBW0fmHHzLrI%3D"],["status","live"],["p","9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1719911364"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/569180c5-adec-40a6-a41b-513f39ded13a.m3u8"],["current_participants","0"],["t","zaplamp"],["t","lnbits"],["t","zapathon"],["t","internal:art"],["goal","66d73e8f3de742e70e3f5b1c30ff2a028fae0d4f1efad53089172e5c05563579"]],"content":"","sig":"4321619ff3aa63387aefc7403baea01317a7c408cfa2547546046e354e4a765af886ee9c509f1ca6043be7cf01bdff696cf521261316c5261a2a42eed87e5289"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
    }){
        LiveEventsBanner(showLiveEventsBanner: .constant(true))
    }
}

#Preview("Integrated banner") {
    PreviewContainer({ pe in
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // live event
            ###"["EVENT","LIVEEVENT-LIVE2",{"kind":30311,"id":"03082afe5364b086293a60c3fc982d5265083af66b726cecd0978d3f0d5be1e0","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720098927,"tags":[["d","569180c5-adec-40a6-a41b-513f39ded13a"],["title",""],["summary","Send a zap to flash the lamp! There is a ~15 sec between your zap and the stream."],["image","https://dvr.zap.stream/zap-stream-dvr/569180c5-adec-40a6-a41b-513f39ded13a/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277007695\u0026Signature=Zqbwvwam70uT9UKRBW0fmHHzLrI%3D"],["status","live"],["p","9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1719911364"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/569180c5-adec-40a6-a41b-513f39ded13a.m3u8"],["current_participants","0"],["t","zaplamp"],["t","lnbits"],["t","zapathon"],["t","internal:art"],["goal","66d73e8f3de742e70e3f5b1c30ff2a028fae0d4f1efad53089172e5c05563579"]],"content":"","sig":"4321619ff3aa63387aefc7403baea01317a7c408cfa2547546046e354e4a765af886ee9c509f1ca6043be7cf01bdff696cf521261316c5261a2a42eed87e5289"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
    }){
        NBNavigationStack {
            NXList(plain: true) {
                Color.clear
                    .frame(height: 60)
                ForEach(0..<10) { _ in
                    Box {
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                LiveEventsBanner(showLiveEventsBanner: .constant(true))
            }
        }
    }
}



