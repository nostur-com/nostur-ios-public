//
//  ChatRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2024.
//

import SwiftUI

struct ChatRow: View {
    @Environment(\.theme) private var theme
    public let content: ChatRowContent
    public var zoomableId: String = "Default"
    @Binding var selectedContact: NRContact?
    
    var body: some View {
        switch content {
            case .chatConfirmedZap(let confirmedZap):
                ChatConfirmedZapRow(confirmedZap: confirmedZap, zoomableId: zoomableId, selectedContact: $selectedContact)
            case .chatPendingZap(let pendingZap):
                ChatPendingZapRow(pendingZap: pendingZap, zoomableId: zoomableId, selectedContact: $selectedContact)
            case .chatMessage(let nrChat):
                ChatMessageRow(nrChat: nrChat, zoomableId: zoomableId, selectedContact: $selectedContact)
        }
    }
}

enum ChatRowContent: Identifiable {
    case chatMessage(NRChatMessage)
    case chatPendingZap(NRChatPendingZap)
    case chatConfirmedZap(NRChatConfirmedZap)
    
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
    
    var nrContact: NRContact? {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.contact
            case .chatPendingZap(let pendingZap):
                pendingZap.contact
            case .chatMessage(let nrChat):
                nrChat.contact
        }
    }
    
    var missingPs: Set<String> {
        switch self {
            case .chatConfirmedZap(let confirmedZap):
                confirmedZap.contact == nil ? Set([confirmedZap.zapRequestPubkey]) : Set<String>()
            case .chatPendingZap(let pendingZap):
                pendingZap.contact == nil ? Set([pendingZap.pubkey]) : Set<String>()
            case .chatMessage(let nrChat):
                nrChat.missingPs
        }
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
    
    var contact: NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.pfpAttributes.contact = newValue
            }
        }
    }
    var pfpAttributes: PFPAttributes
    
    var via: String?
    
    init(id: String, pubkey: String, createdAt: Date, aTag: String, amount: Int64, nxEvent: NXEvent, content: [ContentElement], contact: NRContact? = nil, via: String? = nil) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.aTag = aTag
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.via = via
        
        if let contact { // From param
            self.pfpAttributes = PFPAttributes(contact: contact, pubkey: pubkey)
        }
        else if let cachedNRContact = NRContactCache.shared.retrieveObject(at: pubkey) { // from cache
            self.pfpAttributes = PFPAttributes(contact: cachedNRContact, pubkey: pubkey)
        }
        else if let contact = Contact.fetchByPubkey(pubkey, context: bg()) { // from db
            self.pfpAttributes = PFPAttributes(contact: NRContact.instance(of: pubkey, contact: contact), pubkey: pubkey)
        }
        else { // we dont have it
            self.pfpAttributes = PFPAttributes(pubkey: pubkey)
        }
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
    
    var contact: NRContact?  {
        get { pfpAttributes.contact }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.pfpAttributes.contact = newValue
            }
        }
    }
    var pfpAttributes: PFPAttributes
    
    var via: String?
    
    init(id: String, zapRequestId: String, zapRequestPubkey: String, zapRequestCreatedAt: Date, amount: Int64, nxEvent: NXEvent, content: [ContentElement], contact: NRContact? = nil, via: String? = nil) {
        self.id = id
        self.zapRequestId = zapRequestId
        self.zapRequestPubkey = zapRequestPubkey
        self.zapRequestCreatedAt = zapRequestCreatedAt
        self.amount = amount
        self.nxEvent = nxEvent
        self.content = content
        self.via = via
        
        if let contact { // From param
            self.pfpAttributes = PFPAttributes(contact: contact, pubkey: zapRequestPubkey)
        }
        else if let cachedNRContact = NRContactCache.shared.retrieveObject(at: zapRequestPubkey) { // from cache
            self.pfpAttributes = PFPAttributes(contact: cachedNRContact, pubkey: zapRequestPubkey)
        }
        else if let contact = Contact.fetchByPubkey(zapRequestPubkey, context: bg()) { // from db
            self.pfpAttributes = PFPAttributes(contact: NRContact.instance(of: zapRequestPubkey, contact: contact), pubkey: zapRequestPubkey)
        }
        else { // we dont have it
            self.pfpAttributes = PFPAttributes(pubkey: zapRequestPubkey)
        }
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
