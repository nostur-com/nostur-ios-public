//
//  ConversationRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct ConversationRowView: View {
    @ObservedObject private var conv: Conversation
    @ObservedObject private var nrContact: NRContact
    private var unread: Int { conv.unread }
    
    init(_ conv: Conversation) {
        self.conv = conv
        nrContact = NRContact.instance(of: conv.contactPubkey)
    }

    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: conv.contactPubkey, pictureUrl: nrContact.pictureUrl)
                .onAppear {
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.enqueue(pTag: conv.contactPubkey)
                    }
                }
                .onDisappear {
                    if nrContact.metadata_created_at == 0 {
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
                HStack(alignment: .top, spacing: 5) {
                    Group {
                        Text(nrContact.anyName)
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        
                        PossibleImposterLabelView(nrContact: nrContact)
                    }
                }
                .onAppear {
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.enqueue(pTag: nrContact.pubkey)
                    }
                }
                .onDisappear {
                    if nrContact.metadata_created_at == 0 {
                        QueuedFetcher.shared.dequeue(pTag: nrContact.pubkey)
                    }
                }
                Text(conv.mostRecentMessage).foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
