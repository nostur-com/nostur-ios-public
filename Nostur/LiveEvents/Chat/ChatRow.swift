//
//  ChatRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2024.
//

import SwiftUI
import NostrEssentials

struct ChatRow: View, Equatable {
    @Environment(\.theme) private var theme
    public let content: ChatRowContent
    public let displayUserAgent: Bool
    public var zoomableId: String = "Default"
    public let onReplyPreviewTap: (String) -> Void
    @Binding var selectedContact: NRContact?

    init(
        content: ChatRowContent,
        displayUserAgent: Bool = SettingsStore.shared.displayUserAgentEnabled,
        zoomableId: String = "Default",
        selectedContact: Binding<NRContact?>,
        onReplyPreviewTap: @escaping (String) -> Void = { _ in }
    ) {
        self.content = content
        self.displayUserAgent = displayUserAgent
        self.zoomableId = zoomableId
        self.onReplyPreviewTap = onReplyPreviewTap
        _selectedContact = selectedContact
    }

    static func == (lhs: ChatRow, rhs: ChatRow) -> Bool {
        lhs.content.renderIdentity == rhs.content.renderIdentity &&
        lhs.displayUserAgent == rhs.displayUserAgent &&
        lhs.zoomableId == rhs.zoomableId
    }
    
    var body: some View {
        switch content {
            case .chatConfirmedZap(let confirmedZap):
                ChatConfirmedZapRow(confirmedZap: confirmedZap, displayUserAgent: displayUserAgent, zoomableId: zoomableId, selectedContact: $selectedContact)
            case .chatPendingZap(let pendingZap):
                ChatPendingZapRow(pendingZap: pendingZap, displayUserAgent: displayUserAgent, zoomableId: zoomableId, selectedContact: $selectedContact)
            case .chatMessage(let nrChat):
                ChatMessageRow(
                    nrChat: nrChat,
                    displayUserAgent: displayUserAgent,
                    zoomableId: zoomableId,
                    selectedContact: $selectedContact,
                    onReplyPreviewTap: onReplyPreviewTap
                )
            case .roomPresence(let presence):
                RoomPresenceRow(presence: presence)
        }
    }
}

enum ChatRowContent: Identifiable {
    case chatMessage(NRChatMessage)
    case chatPendingZap(NRChatPendingZap)
    case chatConfirmedZap(NRChatConfirmedZap)
    case roomPresence(NRRoomPresence)
    
    var pubkey: String {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.zapRequestPubkey
            case .chatPendingZap(let pendingZap):
                pendingZap.pubkey
            case .chatMessage(let nrChat):
                nrChat.pubkey
            case .roomPresence(let presence):
                presence.pubkey
        }
    }
    
    var createdAt: Date {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.zapRequestCreatedAt
            case .chatPendingZap(let pendingZap):
                pendingZap.createdAt
            case .chatMessage(let nrChat):
                nrChat.createdAt
            case .roomPresence(let presence):
                presence.createdAt
        }
    }
    
    var id: String {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.zapRequestId
            case .chatPendingZap(let pendingZap):
                pendingZap.id
            case .chatMessage(let nrChat):
                nrChat.id
            case .roomPresence(let presence):
                presence.id
        }
    }

    // Includes the row kind because a pending zap is replaced in place by a
    // confirmed zap. Amount is included because aggregated zap rows can retain
    // their identity while their displayed value changes.
    var renderIdentity: String {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                "confirmed:\(id):\(confirmedZap.amount)"
            case .chatPendingZap(let pendingZap):
                "pending:\(id):\(pendingZap.amount)"
            case .chatMessage:
                "message:\(id)"
            case .roomPresence:
                "presence:\(id)"
        }
    }
    
    var nxEvent: NXEvent {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.nxEvent
            case .chatPendingZap(let pendingZap):
                pendingZap.nxEvent
            case .chatMessage(let nrChat):
                nrChat.nxEvent
            case .roomPresence(let presence):
                presence.nxEvent
        }
    }
    
    var nrContact: NRContact {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.nrContact
            case .chatPendingZap(let pendingZap):
                pendingZap.nrContact
            case .chatMessage(let nrChat):
                nrChat.nrContact
            case .roomPresence(let presence):
                presence.nrContact
        }
    }
    
    var missingPs: Set<String> {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
            confirmedZap.nrContact.metadata_created_at == 0 ? Set([confirmedZap.zapRequestPubkey]) : Set<String>()
            case .chatPendingZap(let pendingZap):
                pendingZap.nrContact.metadata_created_at == 0 ? Set([pendingZap.pubkey]) : Set<String>()
            case .chatMessage(let nrChat):
                nrChat.missingPs
            case .roomPresence(let presence):
                presence.nrContact.metadata_created_at == 0 ? Set([presence.pubkey]) : Set<String>()
        }
    }
}

struct NRRoomPresence {
    let id: String
    let pubkey: String
    let createdAt: Date
    let nxEvent: NXEvent
    let nrContact: NRContact

    init(event: NEvent) {
        id = event.id
        pubkey = event.publicKey
        createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt.timestamp))
        nxEvent = NXEvent(pubkey: event.publicKey, kind: event.kind.id)
        nrContact = NRContact.instance(of: event.publicKey)
    }
}

private struct RoomPresenceRow: View {
    @Environment(\.theme) private var theme
    let presence: NRRoomPresence
    @ObservedObject private var nrContact: NRContact

    init(presence: NRRoomPresence) {
        self.presence = presence
        _nrContact = ObservedObject(wrappedValue: presence.nrContact)
    }

    var body: some View {
        HStack {
            MiniPFP(pictureUrl: nrContact.pictureUrl)

            Text(nrContact.anyName)
                .foregroundColor(theme.accent)
                .lineLimit(1)

            Text("joined")
                .foregroundColor(theme.secondary)

            Ago(presence.createdAt)
                .foregroundColor(theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

class NRChatPendingZap {
    var id: String
    var pubkey: String
    var createdAt: Date
    var aTag: String
    var amount: Int64
    
    var nxEvent: NXEvent
    var content: [ContentElement] = []

    var nrContact: NRContact
    
    var via: String?
    
    init(id: String, pubkey: String, createdAt: Date, aTag: String, amount: Int64, nxEvent: NXEvent, content: [ContentElement], via: String? = nil) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.aTag = aTag
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.via = via
        self.nrContact = NRContact.instance(of: pubkey)
    }
}

class NRChatConfirmedZap {
    var id: String
    var zapRequestId: String
    var zapRequestPubkey: String
    var zapRequestCreatedAt: Date
    var amount: Int64
    
    var nxEvent: NXEvent
    var content: [ContentElement] = []
    
    var nrContact: NRContact
    
    var via: String?
    
    init(id: String, zapRequestId: String, zapRequestPubkey: String, zapRequestCreatedAt: Date, amount: Int64, nxEvent: NXEvent, content: [ContentElement], via: String? = nil) {
        self.id = id
        self.zapRequestId = zapRequestId
        self.zapRequestPubkey = zapRequestPubkey
        self.zapRequestCreatedAt = zapRequestCreatedAt
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.via = via
        self.nrContact = NRContact.instance(of: zapRequestPubkey)
    }
}

//@available(iOS 18.0, *)
//#Preview("Pending zap") {
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, viewType: .row)
//    PreviewContainer({ pe in
//        
//    }) {
//        let pendingZap: ChatRowContent = .chatPendingZap(
//            ChatPendingZap(id: "id",
//                           pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
//                           createdAt: .now,
//                           aTag: "aTag",
//                           amount: 21000,
//                           nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
//                           content: [
//                            .text(
//                                AttributedStringWithPs(
//                                    input: "Hello",
//                                    output: NSAttributedString(string: "Hello"),
//                                    pTags: []
//                                )
//                            )
//                           ]
//                          )
//        )
//        ChatRow(content: pendingZap)
//            .environmentObject(vc)
//            .environmentObject(Themes.default)
//    }
//}
//
//@available(iOS 18.0, *)
//#Preview("Confirmed zap") {
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, viewType: .row)
//    PreviewContainer({ pe in
//        
//    }) {
//        let confirmedZap: ChatRowContent = .chatConfirmedZap(
//            ChatConfirmedZap(id: "id",
//                             zapRequestId: "id",
//                             zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", zapRequestCreatedAt: .now,
//                             amount: 210,
//                             nxEvent: NXEvent(
//                                pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
//                                kind: 9734
//                             ),
//                             content: [
//                                .text(
//                                    AttributedStringWithPs(
//                                        input: "Hello",
//                                        output: NSAttributedString(string: "Hello"),
//                                        pTags: []
//                                    )
//                                )
//                             ],
//                             contact: nil
//                          )
//        )
//        ChatRow(content: confirmedZap)
//            .environmentObject(vc)
//            .environmentObject(Themes.default)
//    }
//}
//
//
//@available(iOS 18.0, *)
//#Preview("Both zaps") {
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, viewType: .row)
//    PreviewContainer({ pe in
//        pe.loadContacts()
//    }) {
//        
//        VStack {
//            let pendingZap: ChatRowContent = .chatPendingZap(
//                ChatPendingZap(id: "id",
//                               pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
//                               createdAt: .now,
//                               aTag: "aTag",
//                               amount: 21000,
//                               nxEvent: NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 9734),
//                               content: [
//                                .text(
//                                    AttributedStringWithPs(
//                                        input: "Hello",
//                                        output: NSAttributedString(string: "Hello"),
//                                        pTags: []
//                                    )
//                                ) 
//                               ]
//                              )
//            )
//            ChatRow(content: pendingZap)
//            
//            
//            let confirmedZap: ChatRowContent = .chatConfirmedZap(
//                ChatConfirmedZap(id: "id",
//                                 zapRequestId: "id",
//                                 zapRequestPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", zapRequestCreatedAt: .now,
//                                 amount: 210,
//                                 nxEvent: NXEvent(
//                                    pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
//                                    kind: 9734
//                                 ),
//                                 content: [
//                                    .text(
//                                        AttributedStringWithPs(
//                                            input: "Hello",
//                                            output: NSAttributedString(string: "Hello"),
//                                            pTags: []
//                                        )
//                                    )
//                                 ],
//                                 contact: nil
//                              )
//            )
//            ChatRow(content: confirmedZap)
//           
//        }
//        .environmentObject(vc)
//        .environmentObject(Themes.default)
//    }
//}
