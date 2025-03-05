//
//  ChatTopZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI
import SwiftUIFlow

struct ChatTopZaps: View {
    @EnvironmentObject private var themes: Themes
    let messages: [ChatConfirmedZap]
    
    var body: some View {
        HStack {
            ForEach(messages, id: \.id) { zap in
                ChatZapPill(zap: zap)
            }
        }
    }
}

struct ChatZapPill: View {
    @EnvironmentObject private var themes: Themes
    let zap: ChatConfirmedZap
    
    @State private var pfpURL: URL?
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .foregroundColor(randomColor(seed: zap.zapRequestPubkey))
                .frame(width: 20.0, height: 20.0)
                .overlay {
                    if let pfpURL {
                        MiniPFP(pictureUrl: pfpURL, size: 20.0)
                            .animation(.easeIn, value: pfpURL)
                    }
                }
            Text(zap.amount.satsFormatted)
                .fontWeightBold()
                .foregroundColor(themes.theme.accent)
                .padding(.trailing, 5)
        }
        .background(themes.theme.listBackground.opacity(0.5))
        .foregroundColor(themes.theme.primary)
        .font(.footnote)
        .clipShape(Capsule())
        .onTapGesture {
            if IS_IPHONE {
                if AnyPlayerModel.shared.viewMode == .detailstream {
                    AnyPlayerModel.shared.viewMode = .overlay
                }
                else if LiveKitVoiceSession.shared.visibleNest != nil {
                    LiveKitVoiceSession.shared.visibleNest = nil
                }
            }
            if let nrContact = zap.contact {
                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
            }
            else {
                navigateTo(ContactPath(key: zap.zapRequestPubkey))
            }
        }
        .onAppear {
            guard let pfpURL = zap.contact?.pictureUrl, self.pfpURL != pfpURL else { return }
            self.pfpURL = pfpURL
        }
        .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
            guard profile.pubkey == zap.zapRequestPubkey, pfpURL != profile.pictureUrl else { return }
            withAnimation {
                pfpURL = profile.pictureUrl
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadZaps()
    }) {
        let messages: [ChatConfirmedZap] = [
            ChatConfirmedZap(
                id: "1",
                zapRequestId: "1",
                zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                zapRequestCreatedAt: .now,
                amount: 21000,
                nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
                content: [.text(AttributedStringWithPs(input: "Hello", output: NSAttributedString(string: "Hello"), pTags: []))],
                contact: nil
            ),
            ChatConfirmedZap(
                id: "2",
                zapRequestId: "2",
                zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                zapRequestCreatedAt: .now,
                amount: 1000,
                nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
                content: [.text(AttributedStringWithPs(input: "World", output: NSAttributedString(string: "World"), pTags: []))],
                contact: nil
            )
        ]
        ChatTopZaps(messages: messages)
            .environmentObject(Themes.default)
    }
} 
