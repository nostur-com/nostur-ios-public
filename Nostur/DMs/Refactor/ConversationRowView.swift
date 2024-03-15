//
//  ConversationRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct ConversationRowView: View {
    @ObservedObject private var conv: Conversation
    private var unread: Int { conv.unread }
    
    init(_ conv: Conversation) {
        self.conv = conv
    }

    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: conv.contactPubkey, nrContact: conv.nrContact)
                .onAppear {
                    if let nrContact = conv.nrContact, nrContact.metadata_created_at == 0, let contact = nrContact.contact {
                        EventRelationsQueue.shared.addAwaitingContact(contact)
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
                            
                            if contact.couldBeImposter == 1 {
                                Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                    .padding(.horizontal, 8)
                                    .background(.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .padding(.top, 3)
                                    .layoutPriority(2)
                            }
                        }
                    }
                    .onAppear {
                        if contact.metadata_created_at == 0 {
                            guard let bgContact = contact.contact else { return }
                            EventRelationsQueue.shared.addAwaitingContact(bgContact, debugInfo: "ConversationRowView.001")
                            QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
                        }
                    }
                    .task {
                        guard !SettingsStore.shared.lowDataMode else { return }
                        guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                        guard contact.metadata_created_at != 0 else { return }
                        guard contact.couldBeImposter == -1 else { return }
                        guard !contact.following else { return }
                        guard !NewOnboardingTracker.shared.isOnboarding else { return }
                        
                        let contactAnyName = contact.anyName.lowercased()
                        let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                        let cPubkey = contact.pubkey
                        
                        bg().perform { [weak conv] in
                            guard let conv else { return }
                            guard let account = account() else { return }
                            guard account.publicKey == currentAccountPubkey else { return }
                            guard let similarContact = account.follows.first(where: {
                                $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName)
                            }) else { return }
                            guard let cPic = contact.pictureUrl, similarContact.picture != nil, let wotPic = similarContact.pictureUrl else { return }
                            Task.detached(priority: .background) {
                                let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                                DispatchQueue.main.async { [weak contact] in
                                    guard let contact else { return }
                                    guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                                    if similarPFP && contact.couldBeImposter != 1 {
                                        conv.objectWillChange.send() // need to rerender
                                    }
                                    contact.couldBeImposter = similarPFP ? 1 : 0
                                    bg().perform { [weak contact] in
                                        guard let contact else { return }
                                        guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                        contact.contact?.couldBeImposter = similarPFP ? 1 : 0
            //                            DataProvider.shared().bgSave()
                                    }
                                }
                            }
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
