//
//  ChatTopZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI
import SwiftUIFlow

struct ChatTopZaps: View {
    @Environment(\.theme) private var theme
    let messages: [NRChatConfirmedZap]
    
    var body: some View {
        HStack {
            ForEach(messages, id: \.id) { zap in
                ChatZapPill(zap: zap)
            }
        }
    }
}

struct ChatZapPill: View {
    @Environment(\.theme) private var theme
    private let zap: NRChatConfirmedZap
    @ObservedObject private var nrContact: NRContact
    
    init(zap: NRChatConfirmedZap) {
        self.zap = zap
        self.nrContact = zap.nrContact
    }
    
    var body: some View {
        HStack(spacing: 5) {
            MiniPFP(pictureUrl: nrContact.pictureUrl, size: 20.0, fallBackColor: randomColor(seed: zap.zapRequestPubkey))
                .animation(.easeIn, value: nrContact.pictureUrl)
            
//                .frame(width: 20.0, height: 20.0)
            Text(zap.amount, format: .number.notation((.compactName)))
                .fontWeightBold()
                .foregroundColor(theme.accent)
                .padding(.trailing, 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(theme.primary)
        .font(.footnote)
        .modifier {
            if #available(iOS 26.0, *) {
                $0
                    .glassEffect(.clear.tint(theme.listBackground.opacity(0.35)))
            }
            else {
                $0
                    .background(theme.listBackground.opacity(0.85))
                    .frame(height: 34.0)
                    .clipShape(.rect(cornerRadius: 30))
                    .frame(height: 44.0)
            }
        }
        .clipShape(Capsule())
        .onTapGesture {
            if AnyPlayerModel.shared.viewMode == .detailstream {
                AnyPlayerModel.shared.viewMode = .overlay
            }
            else if LiveKitVoiceSession.shared.visibleNest != nil {
                LiveKitVoiceSession.shared.visibleNest = nil
            }
            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName), context: "Default")
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadZaps()
    }) {
        let messages: [NRChatConfirmedZap] = [
            NRChatConfirmedZap(
                id: "1",
                zapRequestId: "1",
                zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                zapRequestCreatedAt: .now,
                amount: 21000,
                nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
                content: [.text(AttributedStringWithPs(input: "Hello", output: NSAttributedString(string: "Hello"), pTags: []))]
            ),
            NRChatConfirmedZap(
                id: "2",
                zapRequestId: "2",
                zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                zapRequestCreatedAt: .now,
                amount: 1000,
                nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
                content: [.text(AttributedStringWithPs(input: "World", output: NSAttributedString(string: "World"), pTags: []))]
            )
        ]
        ChatTopZaps(messages: messages)
            .environmentObject(Themes.default)
    }
} 
