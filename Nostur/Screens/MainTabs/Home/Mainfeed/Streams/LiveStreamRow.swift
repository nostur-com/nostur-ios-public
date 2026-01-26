//
//  LiveStreamRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2026.
//

import SwiftUI

struct LiveStreamRow: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var liveEvent: NRLiveEvent
    private var fullWidth: Bool = false
    private var hideFooter: Bool = false
    private var navTitleHidden: Bool = false
    private var forceAutoload: Bool
    
    private var shouldAutoload: Bool {
        return !liveEvent.isNSFW  && (forceAutoload || SettingsStore.shouldAutodownload(liveEvent) || nxViewingContext.contains(.screenshot))
    }
    
    init(liveEvent: NRLiveEvent, fullWidth: Bool = false, hideFooter: Bool = false, navTitleHidden: Bool = false, forceAutoload: Bool = false) {
        self.liveEvent = liveEvent
        self.fullWidth = fullWidth
        self.hideFooter = hideFooter
        self.navTitleHidden = navTitleHidden
        self.forceAutoload = forceAutoload
    }
    
    @State private var showMiniProfile = false
    @State private var didLoad = false
    
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
    
    var body: some View {
        VStack(alignment: .leading) {
            if let title = liveEvent.title {
                Text(title)
                    .font(.title2)
                    .fontWeightBold()
                    .lineLimit(1)
            }
            
            HStack {
                HStack {
                    ZStack(alignment: .leading) {
                        ForEach(liveEvent.participantsOrSpeakers.indices, id: \.self) { index in
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: CGFloat(index) * 25)
                                PFP(pubkey: liveEvent.participantsOrSpeakers[index].pubkey, nrContact: liveEvent.participantsOrSpeakers[index], size: 50.0)
                            }
                            .id(liveEvent.participantsOrSpeakers[index].pubkey)
                        }
                    }
                    .frame(height: 50.0)
                }
                
                eventStatus
            }
            
            if let summary = liveEvent.summary, (liveEvent.title ?? "") != summary {
                Text(summary)
                    .lineLimit(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // better just fetch all Ps for now
            if !liveEvent.missingPs.isEmpty {
                QueuedFetcher.shared.enqueue(pTags: liveEvent.missingPs)
            }
        }
        .padding(10)
        .padding(.bottom, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            setSelectedTab("Main")
            if let status = liveEvent.status, status == "planned" {
                navigateTo(liveEvent, context: containerID)
            }
            else if liveEvent.isLiveKit && (IS_CATALYST || IS_IPAD) { // Always do nests in tab on ipad/desktop
                navigateTo(liveEvent, context: containerID)
            }
            else {
                // LOAD NEST
                if liveEvent.isLiveKit {
                    LiveKitVoiceSession.shared.activeNest = liveEvent
                }
                // ALREADY PLAYING IN .OVERLAY, TOGGLE TO .DETAILSTREAM
                else if AnyPlayerModel.shared.nrLiveEvent?.id == liveEvent.id {
                    AnyPlayerModel.shared.viewMode = .detailstream
                }
                // LOAD NEW .DETAILSTREAM
                else {
                    Task {
                        await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: liveEvent, availableViewModes: [.detailstream, .overlay, .audioOnlyBar])
                    }
                }
            }
        }
        .background(theme.listBackground)
        .padding(.bottom, GUTTER)
    }
    
    // Copy paste from LiveEventDetail (rec removed)
    @ViewBuilder
    private var eventStatus: some View {
        if streamHasEnded {
            HStack {
                Text("Stream has ended")
                    .foregroundColor(.secondary)
            }
        }
        else if liveEvent.totalParticipants > 0 {
            Label("\(liveEvent.totalParticipants.description) tuned in", systemImage: "person.fill")
                .labelStyle(CompactLabelStyle())
                .fontWeightBold()
        }
        else if let scheduledAt = liveEvent.scheduledAt {
            HStack {
                Image(systemName: "calendar")
                Text(scheduledAt.formatted())
            }
                .padding(.top, 10)
                .font(.footnote)
                .foregroundColor(theme.secondary)
        }
    }
    
    private var streamHasEnded: Bool {
        if let status = liveEvent.status, status == "ended" {
            return true
        }
        return false
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":9720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
    }) {
        if let event = PreviewFetcher.fetchEvent("8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601") {
            LiveStreamRow(liveEvent: NRLiveEvent(event: event))
        }
    }
}
