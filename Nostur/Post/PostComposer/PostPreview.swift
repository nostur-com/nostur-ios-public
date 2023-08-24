//
//  PostPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/04/2023.
//

import SwiftUI

struct PostPreview: View {
    @StateObject var dim = DIMENSIONS()
    @Environment(\.dismiss) var dismiss
    let nrPost:NRPost
    let sendNow:() -> Void
    @Binding var uploading:Bool

    // This previewEvent is not saved in database
    // Code is basically from Event.saveEvent, without unnecessary bits
    
    init(nrPost: NRPost, sendNow: @escaping () -> Void, uploading:Binding<Bool>) {
        self.nrPost = nrPost
        self.sendNow = sendNow
        _uploading = uploading
    }
    
    var body: some View {
        ScrollView {
            Color.clear.frame(height: 0)
                .modifier(SizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    guard size.width > 0 else { return }
                    dim.listWidth = size.width
                }
            AnyStatus()
            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, isDetail: true)
                .padding(10)
                .disabled(true)
                .environmentObject(dim)
            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized:"Back", comment:"Button to go back")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sendNow()
                } label: {
                    if (uploading) {
                        ProgressView()
                    }
                    else {
                        Text("Post.verb", comment: "Button to post (publish) a new post")
                    }
                }
                .buttonStyle(.borderedProminent)
                .cornerRadius(20)
                .disabled(uploading)
            }
        }
        .navigationTitle(String(localized: "Post preview", comment: "Navigation title for Post Preview screen"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

func createPreviewEvent(_ event:NEvent) -> Event {
    let context = DataProvider.shared().bg
    let previewEvent = Event(context: context)
    previewEvent.insertedAt = Date.now
    previewEvent.id = event.id
    previewEvent.kind = Int64(event.kind.id)
    previewEvent.created_at = Int64(event.createdAt.timestamp)
    previewEvent.content = event.content
//    previewEvent.sig = event.signature
    previewEvent.pubkey = event.publicKey
    previewEvent.likesCount = 0
    previewEvent.isRepost = event.kind == .repost
    previewEvent.contact = Contact.fetchByPubkey(event.publicKey, context: context)
    previewEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
    previewEvent.isPreview = true
            
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
    @State static var uploading = false
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadZaps()
        }) {
            NavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    PostPreview(nrPost: nrPost, sendNow: { print("send!") }, uploading: $uploading)
                }
            }
        }
    }
}
