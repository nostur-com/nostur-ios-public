//
//  ConversationRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct ConversationRowView: View {
    @ObservedObject private var conv: Conversation
    @StateObject private var pfpAttributes: PFPAttributes
    private var unread: Int { conv.unread }
    
    init(_ conv: Conversation) {
        self.conv = conv
        _pfpAttributes = StateObject(wrappedValue: PFPAttributes(contact: conv.nrContact, pubkey: conv.contactPubkey))
    }

    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: conv.contactPubkey, pictureUrl: pfpAttributes.pfpURL)
                .onAppear {
                    if let nrContact = conv.nrContact, nrContact.metadata_created_at == 0, let contact = nrContact.contact {
                        EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "ConversationRowView.001")
                        QueuedFetcher.shared.enqueue(pTag: conv.contactPubkey)
                    }
                }
                .onDisappear {
                    if let nrContact = conv.nrContact, nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: conv.contactPubkey)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal,6)
                            .background(Capsule().foregroundColor(.red))
//                                .offset(x:15, y: -20)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                if let contact = conv.nrContact {
                    HStack(alignment: .top, spacing: 5) {
                        Group {
                            Text(contact.anyName)
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            
                            PossibleImposterLabelView(pfp: pfpAttributes)
                        }
                    }
                    .onAppear {
                        if contact.metadata_created_at == 0 {
                            guard let bgContact = contact.contact else { return }
                            EventRelationsQueue.shared.addAwaitingContact(bgContact, debugInfo: "ConversationRowView.002")
                            QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
                        }
                    }
                    .onDisappear {
                        if contact.metadata_created_at == 0 {
                            QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
                        }
                    }
                }
                else {
                    Text(conv.contactPubkey.prefix(11))
                        .onAppear {
                            bg().perform {
                                EventRelationsQueue.shared.addAwaitingEvent(conv.mostRecentEvent, debugInfo: "ConversationRowView.002")
                                QueuedFetcher.shared.enqueue(pTag: conv.contactPubkey)
                            }
                        }
                        .onDisappear {
                            QueuedFetcher.shared.dequeue(pTag: conv.contactPubkey)
                        }
                }
                Text(conv.mostRecentMessage).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
