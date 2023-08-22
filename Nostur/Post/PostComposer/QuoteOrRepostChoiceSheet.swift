//
//  QuoteOrRepostChoiceSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/03/2023.
//

import SwiftUI

struct QuoteOrRepostChoiceSheet: View {
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    @Environment(\.dismiss) var dismiss
    
    let originalEvent:Event
    @Binding var quotePostEvent:Event?
    
    var body: some View {
        // repost
        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard let account = ns.account else { return }
                guard account.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                if (ns.account != nil) {
                    
                    // 1. create repost
                    var repost = EventMessageBuilder.makeRepost(original: originalEvent, embedOriginal: true)
                    
                    let cancellationId = UUID()
                    if account.isNC {
                        repost.publicKey = account.publicKey
                        repost = repost.withId()
                        
                        // Save unsigned event:
                        DataProvider.shared().bg.perform {
                            let savedEvent = Event.saveEvent(event: repost, flags: "nsecbunker_unsigned")
                            savedEvent.cancellationId = cancellationId
                            DispatchQueue.main.async {
                                sendNotification(.newPostSaved, savedEvent)
                            }
                            DataProvider.shared().bgSave()
                            dismiss()
                            DispatchQueue.main.async {
                                NosturState.shared.nsecBunker?.requestSignature(forEvent: repost, whenSigned: { signedEvent in
                                    DataProvider.shared().bg.perform {
                                        savedEvent.sig = signedEvent.signature
                                        savedEvent.flags = "awaiting_send"
                                        savedEvent.cancellationId = cancellationId
                                        savedEvent.updateNRPost.send(savedEvent)
                                        DispatchQueue.main.async {
                                            Unpublisher.shared.publishNow(originalEvent.toNEvent()) // publish original
                                            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                                            
                                            sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: originalEvent.id))
                                        }
                                    }
                                })
                            }
                        }
                    }
                    else if let signedEvent = try? NosturState.shared.signEvent(repost) {
                        DataProvider.shared().bg.perform {
                            let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send")
                            savedEvent.cancellationId = cancellationId
                            
                            DataProvider.shared().bgSave()
                            dismiss()
                            if ([1,6,9802,30023].contains(savedEvent.kind)) {
                                DispatchQueue.main.async {
                                    sendNotification(.newPostSaved, savedEvent)
                                }
                            }
                        }
                        Unpublisher.shared.publishNow(originalEvent.toNEvent()) // publish original
                        _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                        
                        sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: originalEvent.id))
                    }
                }
            } label: { Label(String(localized:"Repost", comment:"Button to Repost a post"), systemImage: "arrow.2.squarepath").padding(.vertical, 5) }
            
            // quote tweet
            Button {
                quotePostEvent = originalEvent
                dismiss()
            } label: { Label(String(localized: "Quote post", comment:"Button to Quote a post"), systemImage: "square.and.pencil").padding(.vertical, 5) }
                .padding(.vertical, 10)
            
            // cancel
            Button {
                dismiss()
            } label: { Text("Cancel").frame(width: 250) }
                .padding(.vertical, 10)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 10)
        
    }
}

struct QuoteOrRepostChoiceSheet_Previews: PreviewProvider {
    
    @State static var quotePostEvent:Event? = nil
    
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
                let event = PreviewFetcher.fetchEvent()
                
                if let event {
                    QuoteOrRepostChoiceSheet(originalEvent: event, quotePostEvent: $quotePostEvent)
                }
            }
        }
    }
}
