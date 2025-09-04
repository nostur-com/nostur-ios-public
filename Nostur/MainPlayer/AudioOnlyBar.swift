//
//  AudioOnlyBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/04/2025.
//

import SwiftUI

struct AudioOnlyBar: View {
    @Environment(\.theme) private var theme
    @ObservedObject var vm: AnyPlayerModel = .shared
    
    private var title: String {
        if let title = vm.nrLiveEvent?.title, title != "" {
            return title
        }
        else if let anyName = vm.nrPost?.anyName {
            return anyName
        }
        else if let names = vm.nrLiveEvent?.participantsOrSpeakers.map({ $0.anyName }).joined(separator: ", ") {
            return names
        }
        return "Untitled"
    }
    
    private var subtitle: String {
        let summary = vm.nrLiveEvent?.summary ?? ""
        if summary != title {
            return summary
        }
        return ""
    }
    
    var body: some View {
        theme.accent
            .frame(height: AUDIOONLYPILL_HEIGHT)
            .overlay {
                HStack(spacing: 10) {
                    if let liveEvent = vm.nrLiveEvent {
                        Color.clear
                            .frame(width: 40, height: 40)
                            .overlay {
                                HStack {
                                    ZStack(alignment: .leading) {
                                        ForEach(liveEvent.participantsOrSpeakers.indices, id: \.self) { index in
                                            HStack(spacing: 0) {
                                                Color.clear
                                                    .frame(width: CGFloat(index) * 8)
                                                PFP(pubkey: liveEvent.participantsOrSpeakers[index].pubkey, nrContact: liveEvent.participantsOrSpeakers[index], size: 30.0)
                                            }
                                            .id(liveEvent.participantsOrSpeakers[index].pubkey)
                                        }
                                    }
                                    .frame(height: 34.0)
                                }
                            }
                    }
                    else if let nrPost = vm.nrPost {
                        Color.clear
                            .frame(width: 40, height: 40)
                            .overlay {
                                PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 30.0)
                            }
                    }
                    
                    VStack(alignment: .leading) {
                        Text(title)
                            .lineLimit(1)
                        if subtitle != "" {
                            Text(subtitle)
                                .lineLimit(1)
                                .font(.footnote)
                        }
                    }
                    .foregroundColor(Color.white)
                    
                    Spacer()
                    
                    Color.clear
                        .frame(width: 40, height: 40)
                        .overlay {
                            if vm.didFinishPlaying {
                                Button("Replay", systemImage: "memories") {
                                    vm.replay()
                                }
                                .foregroundColor(Color.white)
                                .font(.title)
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                            }
                            else {
                                Button(action: {
                                    if vm.isPlaying {
                                        vm.pauseVideo()
                                    }
                                    else {
                                        vm.playVideo()
                                    }
                                }) {
                                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                        .foregroundColor(Color.white)
                                        .font(.title)
                                }
                            }
                        }
                }
                .padding(.horizontal, 5)
                .frame(height: AUDIOONLYPILL_HEIGHT)
            }
            .onTapGesture {
                withAnimation {
                    vm.toggleViewMode()
                }
            }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
        pe.parseMessages([
            ###"["EVENT","sub",{"kind":30311,"id":"7f0ddf8fb370af54a5e2a3c009bc437808a7cc69a4fdc7104d4f0ea2f6dd7f3f","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1745898657,"tags":[["d","537a365c-f1ec-44ac-af10-22d14a7319fb"],["title","NoGood Radio"],["summary","NoGood Radio is a 24/7 pirate radio station running on scrap parts and broadcasting from a basement somewhere."],["image","https://blossom.nogood.studio/6d5bb489e87c2f2db2a0fa61fd2bfca9f6d4f50e05b7caf1784644886c0e4ff6"],["status","live"],["p","55f04590674f3648f4cdc9dc8ce32da2a282074cd0b020596ee033d12d385185","wss://relay.zap.stream","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev","wss://relay.fountain.fm"],["starts","1739464332"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/537a365c-f1ec-44ac-af10-22d14a7319fb.m3u8"],["current_participants","1"],["t","Radio"],["t","24/7"],["t","internal:music"]],"content":"","sig":"ca3fabdf33d0a07f884e4f4f0c63ceae4d3fc31f99c5a370f19b43780cc6aaaf47cd99e5d0bc27219626fae12f3f201b5e8369452e19b1e03818c01c9fe947c2"}]"###
        ])
    }) {
        if let nrPost = PreviewFetcher.fetchNRPost("7f0ddf8fb370af54a5e2a3c009bc437808a7cc69a4fdc7104d4f0ea2f6dd7f3f") {
            let _ = AnyPlayerModel.shared.nrPost = nrPost
            AudioOnlyBar()
        }
    }
}


struct AudioOnlyBarSpace: View {
    @ObservedObject private var apm: AnyPlayerModel = .shared
    
    var body: some View {
        if apm.viewMode == .audioOnlyBar {
            // Spacer for OverlayVideo here
            Color.clear
                .frame(height: AUDIOONLYPILL_HEIGHT)
        }
    }
}
