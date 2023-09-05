//
//  ConversationRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct ConversationRowView: View {
    @ObservedObject var conv:Conversation
    var unread:Int { conv.unread }
    
    init(_ conv: Conversation) {
        self.conv = conv
    }

    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: conv.contactPubkey, nrContact: conv.nrContact)
                .onAppear {
                    if let nrContact = conv.nrContact, nrContact.metadata_created_at == 0 {
                        EventRelationsQueue.shared.addAwaitingContact(nrContact.contact)
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
                HStack {
                    if let nrContact = conv.nrContact {
                        NameAndNip(contact: nrContact)
                    }
                    else {
                        EmptyView()
                            .onAppear {
                                EventRelationsQueue.shared.addAwaitingEvent(conv.mostRecentEvent)
                                QueuedFetcher.shared.enqueue(pTag: conv.contactPubkey)
                            }
                            .onDisappear {
                                QueuedFetcher.shared.dequeue(pTag:  conv.contactPubkey)
                            }
                    }
                    
                    Ago(conv.mostRecentDate).layoutPriority(1)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
                Text(conv.mostRecentMessage).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
