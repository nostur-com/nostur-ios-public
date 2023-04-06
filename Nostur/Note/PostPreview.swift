//
//  PostPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/04/2023.
//

import SwiftUI

struct PostPreview: View {
    
    @Environment(\.dismiss) var dismiss
    let previewEvent:Event
    let sendNow:() -> Void
    let vPost:VPost

    // This previewEvent is not saved in database
    // Code is basically from Event.saveEvent, without unnecessary bits
    
    init(previewEvent: Event, sendNow: @escaping () -> Void) {
        self.previewEvent = previewEvent
        self.sendNow = sendNow
        self.vPost = previewEvent.toVPost()!
    }
    
    var body: some View {
        ScrollView {
            NoteRow(vPost: vPost)
                .boxShadow()
            Spacer()
        }
        .padding(10)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    DataProvider.shared().viewContext.delete(previewEvent)
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    DataProvider.shared().viewContext.delete(previewEvent)
                    sendNow()
                } label: {
                    Text("Post")
                }
                .buttonStyle(.borderedProminent)
                .cornerRadius(20)
            }
        }
        .navigationTitle("Post preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

func createPreviewEvent(_ event:NEvent) -> Event {
    let context = DataProvider.shared().viewContext
    let previewEvent = Event(context: context)
    previewEvent.insertedAt = Date.now
    previewEvent.id = event.id
    previewEvent.kind = Int64(event.kind.id)
    previewEvent.created_at = Int64(event.createdAt.timestamp)
    previewEvent.content = event.content
//    previewEvent.sig = event.signature
    previewEvent.pubkey = event.publicKey
    previewEvent.likesCount = 0
    previewEvent.liked = false
    previewEvent.isRepost = event.kind == .repost
    previewEvent.contact = Contact.fetchByPubkey(event.publicKey, context: context)
    previewEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
            
    if (event.kind == .textNote) {
        // THIS EVENT REPLYING TO SOMETHING
        // CACHE THE REPLY "E" IN replyToId
        if let replyToEtag = event.replyToEtag() {
            previewEvent.replyToId = replyToEtag.id
            
            // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
            if let replyTo = try? Event.fetchEvent(id: replyToEtag.id, context: context) {
                previewEvent.replyTo = replyTo
            }
        }
        
        // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO
        // DO THE SAME AS WITH THE REPLY BEFORE
        if let replyToRootEtag = event.replyToRootEtag() {
            if (replyToRootEtag.id != previewEvent.replyToId) { // If reply root is same as reply, dont double add.
                previewEvent.replyToRootId = replyToRootEtag.id
                if (previewEvent.replyToId == nil) { // IF IT HAS ONLY A ROOT REPLY, NO NORMAL REPLY: THEN REPLYTOROOT = REPLYTO
                    previewEvent.replyToId = replyToRootEtag.id
                    
                    // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                    if let replyToRoot = try? Event.fetchEvent(id: replyToRootEtag.id, context: context) {
                        previewEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                    }
                }
            }
        }
        

        var contactsInThisEvent = [Contact]()
        for pTag in event.pTags() {
            if let contact = Contact.fetchByPubkey(pTag, context: context) {
                contactsInThisEvent.append(contact)
            }
        }
        previewEvent.addToContacts(NSSet(array: contactsInThisEvent))

    }

    // handle REPOST with normal mentions in .kind 1
    // todo handle first nostr:nevent or not?
    if event.kind == .textNote, let firstE = event.firstMentionETag() {
        previewEvent.firstQuoteId = firstE.id
        // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
        if let firstQuote = try? Event.fetchEvent(id: previewEvent.firstQuoteId!, context: context) {
            previewEvent.firstQuote = firstQuote
        }
    }
    
    return previewEvent
}

struct PostPreview_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let event = PreviewFetcher.fetchEvent() {
                PostPreview(previewEvent: event, sendNow: { print("send!") })
            }
        }
        .withPreviewEnvironment()
    }
}
