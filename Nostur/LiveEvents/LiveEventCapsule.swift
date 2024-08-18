//
//  LiveEventCapsule.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import SwiftUI

struct LiveEventCapsule: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject public var liveEvent: NRLiveEvent
    public var onRemove: (String) -> ()
    
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        HStack {
            // TODO: Refactor and reuse FoundAccountPFPs
            ZStack(alignment: .leading) {
                ForEach(liveEvent.participantsOrSpeakers.indices, id: \.self) { index in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: CGFloat(index) * 12)
                        PFP(pubkey: liveEvent.participantsOrSpeakers[index].pubkey, nrContact: liveEvent.participantsOrSpeakers[index], size: 20.0)
                    }
                    .id(liveEvent.participantsOrSpeakers[index].pubkey)
                }
            }
            .frame(height: 34.0)
            Text((liveEvent.title ?? liveEvent.summary) ?? "Now live").lineLimit(1)
                .fontWeightBold()
            Spacer()
            Image(systemName: "waveform")
                .symbolEffectPulse()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .background(themes.theme.accent)
        .frame(height: 34.0)
        .clipShape(.rect(cornerRadius: 30))
        .frame(height: 44.0)
        .contentShape(Rectangle())
        .offset(y: dragOffset.height)
        .gesture(
            TapGesture()
               .onEnded {
                   if IS_CATALYST {
                       navigateTo(liveEvent)
                   }
                   else {
                       LiveKitVoiceSession.shared.activeNest = liveEvent
                   }
               }
               .simultaneously(with: DragGesture()
                   .onChanged { value in
                       if value.translation.height < 0 { // Only allow upward swipes
                           dragOffset = value.translation
                       }
                   }
                   .onEnded { value in
                       if value.translation.height < -50 { // Adjust the threshold as needed
                           onRemove(liveEvent.id)
                       }
                       dragOffset = .zero
                   }
               )
       )
    }
}


#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
        pe.parseMessages([
            ###"["EVENT","LIVE",{"content":"","created_at":1718076971,"id":"1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2","kind":30311,"pubkey":"8a0969377e9abfe215e99f02e1789437892526b1d1e0b1ca4ed7cbf88b1cc421","sig":"2eb76ceda6c1345465998fe14cf53da308880fd1cf2f70e6c0d6e248d1a903105301f99f04c8e230272aaf0c8ee5a35c7c2b03cc63e64e62e88b7b55111f3920","tags":[["d","1718063831277"],["title","Corny Chat News"],["summary","Weekly news roundup providing a summary of the weeks headlines and topical discussion regarding Nostr, Lightning, Bitcoin, Geopolitics and Clown World, Humor and more."],["image","https://image.nostr.build/ea30115d83b1d3c303095a0a3349514ca2a88e12b9c5dd7fd92e984502be55f0.jpg"],["service","https://cornychat.com/cornychatnews"],["streaming","https://cornychat.com/cornychatnews"],["starts","1718063831"],["ends","1718080571"],["status","live"],["current_participants","7"],["t","talk"],["t","talk show"],["L","com.cornychat"],["l","cornychat.com","com.cornychat"],["l","audiospace","com.cornychat"],["r","https://cornychat.com/cornychatnews"],["p","50809a53fef95904513a840d4082a92b45cd5f1b9e436d9d2b92a89ce091f164","","Participant"],["p","7cc328a08ddb2afdf9f9be77beff4c83489ff979721827d628a542f32a247c0e","","Participant"],["p","21b419102da8fc0ba90484aec934bf55b7abcf75eedb39124e8d75e491f41a5e","","Room Owner"],["p","52387c6b99cc42aac51916b08b7b51d2baddfc19f2ba08d82a48432849dbdfb2","","Participant"],["p","50de492cfe5472450df1a0176fdf6d915e97cb5d9f8d3eccef7d25ff0a8871de","","Speaker"],["p","9322bd922f20c6fcd9e913454727b3bbc2d096be4811971055a826dda3d4cb0b","","Participant"],["p","cc76679480a4504b963a3809cba60b458ebf068c62713621dda94b527860447d","","Participant"]]}]"###
        ])
    }) {
        if let liveEvent = PreviewFetcher.fetchEvent("1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2") {
            let nrLiveEvent = NRLiveEvent(event: liveEvent)
            LiveEventCapsule(liveEvent: nrLiveEvent, onRemove: { _ in })
        }
    }
}

