//
//  ChatRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2024.
//

import SwiftUI

struct ChatRow: View {
    @State private var didStart = false
    
    public let content: ChatRowContent
    public let theme: Theme
    
    var body: some View {
        switch content {
            case .chatConfirmedZap(let confirmedZap):
            VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill").foregroundColor(.yellow)
                            Text(confirmedZap.amount.satsFormatted)
                                .fontWeightBold()
                        }
                        .padding(.leading, 7)
                        .padding(.trailing, 8)
                        
                        .padding(.vertical, 2)
                        .foregroundColor(Color.white)
                        .background {
                            theme.accent
                                .clipShape(Capsule())
                        }
                        
                        MiniPFP(pictureUrl: confirmedZap.contact?.pictureUrl)
                            .onTapGesture {
                                if IS_IPHONE {
                                    if AnyPlayerModel.shared.viewMode == .detailstream {
                                        AnyPlayerModel.shared.viewMode = .overlay
                                    }
                                    else if LiveKitVoiceSession.shared.visibleNest != nil {
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                                if let nrContact = confirmedZap.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: confirmedZap.zapRequestPubkey))
                                }
                            }
                        
                        Text(confirmedZap.contact?.anyName ?? "...")
                            .onTapGesture {
                                if IS_IPHONE {
                                    if AnyPlayerModel.shared.viewMode == .detailstream {
                                        AnyPlayerModel.shared.viewMode = .overlay
                                    }
                                    else if LiveKitVoiceSession.shared.visibleNest != nil {
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                                if let nrContact = confirmedZap.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: confirmedZap.zapRequestPubkey))
                                }
                            }
                                
                        Ago(confirmedZap.zapRequestCreatedAt)
                            .foregroundColor(theme.secondary)
                    }
                    .foregroundColor(theme.accent)
                    
                    NXContentRenderer(nxEvent: confirmedZap.nxEvent, contentElements: confirmedZap.content, didStart: $didStart)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: 450, alignment: .top)
                        .onAppear {
            //                        if !zapFromAttributes.missingPs.isEmpty {
            //                            bg().perform {
            //                                QueuedFetcher.shared.enqueue(pTags: zapFromAttributes.missingPs)
            //                            }
            //                        }
                        }
                }
            case .chatPendingZap(let pendingZap):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.badge.clock.fill").foregroundColor(.yellow.opacity(0.75))
                            Text(pendingZap.amount.satsFormatted + " sats")
                                .fontWeightBold()
                        }
                        .padding(.leading, 7)
                        .padding(.trailing, 8)
                        
                        .padding(.vertical, 2)
                        .foregroundColor(Color.white)
                        .background {
                            theme.accent
                                .clipShape(Capsule())
                        }
                        
                        MiniPFP(pictureUrl: pendingZap.contact?.pictureUrl)
                            .onTapGesture {
                                if IS_IPHONE {
                                    if AnyPlayerModel.shared.viewMode == .detailstream {
                                        AnyPlayerModel.shared.viewMode = .overlay
                                    }
                                    else if LiveKitVoiceSession.shared.visibleNest != nil {
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                                if let nrContact = pendingZap.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: pendingZap.pubkey))
                                }
                            }
                        Text(pendingZap.contact?.anyName ?? "...")
                            .onTapGesture {
                                if IS_IPHONE {
                                    if AnyPlayerModel.shared.viewMode == .detailstream {
                                        AnyPlayerModel.shared.viewMode = .overlay
                                    }
                                    else if LiveKitVoiceSession.shared.visibleNest != nil {
                                        LiveKitVoiceSession.shared.visibleNest = nil
                                    }
                                }
                                if let nrContact = pendingZap.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: pendingZap.pubkey))
                                }
                            }
                        Ago(pendingZap.createdAt)
                            .foregroundColor(theme.secondary)
                    }
                    .foregroundColor(theme.accent)
                    
                    NXContentRenderer(nxEvent: pendingZap.nxEvent, contentElements: pendingZap.content, didStart: $didStart)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: 450, alignment: .top)
//                        .padding(.leading, 10)
                        .onAppear {
                            //                        if !zapFromAttributes.missingPs.isEmpty {
                            //                            bg().perform {
                            //                                QueuedFetcher.shared.enqueue(pTags: zapFromAttributes.missingPs)
                            //                            }
                            //                        }
                        }
                }
            case .chatMessage(let nrChat):
                ChatMessageRow(nrChat: nrChat)
//                .overlay(alignment: .top) {
//                    Text("chatMessage nrChat")
//                }
        }
    }
}

//#Preview {
//    ChatRow(content: )
//}

enum ChatRowContent: Identifiable {
    case chatMessage(NRChatMessage)
    case chatPendingZap(ChatPendingZap)
    case chatConfirmedZap(ChatConfirmedZap)
    
    var pubkey: String {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.zapRequestPubkey
            case .chatPendingZap(let pendingZap):
                pendingZap.pubkey
            case .chatMessage(let nrChat):
                nrChat.pubkey
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
        }
    }
}

struct ChatPendingZap {
    var id: String
    var pubkey: String
    var createdAt: Date
    var aTag: String
    var amount: Int64
    
    var nxEvent: NXEvent
    var content: [ContentElement] = []
    var contact: NRContact?
    
    init(id: String, pubkey: String, createdAt: Date, aTag: String, amount: Int64, nxEvent: NXEvent, content: [ContentElement], contact: NRContact? = nil) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.aTag = aTag
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.contact = contact ?? NRContact.fetch(pubkey)
    }
}

struct ChatConfirmedZap {
    var id: String
    var zapRequestId: String
    var zapRequestPubkey: String
    var zapRequestCreatedAt: Date
    var amount: Int64
    
    var nxEvent: NXEvent
    var content: [ContentElement] = []
    var contact: NRContact?
    
    init(id: String, zapRequestId: String, zapRequestPubkey: String, zapRequestCreatedAt: Date, amount: Int64, nxEvent: NXEvent, content: [ContentElement], contact: NRContact? = nil) {
        self.id = id
        self.zapRequestId = zapRequestId
        self.zapRequestPubkey = zapRequestPubkey
        self.zapRequestCreatedAt = zapRequestCreatedAt
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.contact = contact ?? NRContact.fetch(zapRequestPubkey)
    }
}

//@available(iOS 18.0, *)
//#Preview("Pending zap") {
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, theme: Themes.default.theme, viewType: .row)
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
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, theme: Themes.default.theme, viewType: .row)
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
//    @Previewable @State var vc = ViewingContext(availableWidth: 200, fullWidthImages: false, theme: Themes.default.theme, viewType: .row)
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
