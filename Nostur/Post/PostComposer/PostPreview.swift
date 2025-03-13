//
//  PostPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/04/2023.
//

import SwiftUI

struct PostPreview: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS // previewDIM from ComposePost
    @Environment(\.dismiss) private var dismissPostPreview
    public let nrPost: NRPost
    public let replyTo: ReplyTo?
    public let quotePost: QuotePost?
    @ObservedObject public var vm: NewPostModel
    @ObservedObject public var typingTextModel: TypingTextModel
    public let onDismiss: () -> Void
    @State private var postPreviewWidth: CGFloat? = nil

    // This previewEvent is not saved in database
    // Code is basically from Event.saveEvent, without unnecessary bits
    
    init(nrPost: NRPost, replyTo: ReplyTo?, quotePost: QuotePost?, vm: NewPostModel, onDismiss: @escaping () -> Void) {
        self.nrPost = nrPost
        self.replyTo = replyTo
        self.quotePost = quotePost
        self.vm = vm
        self.onDismiss = onDismiss
        self.typingTextModel = vm.typingTextModel
    }
    
    private var shouldDisablePostButton: Bool {
        typingTextModel.sending || typingTextModel.uploading || (typingTextModel.text.isEmpty && typingTextModel.pastedImages.isEmpty)
    }

    var body: some View {
        ScrollView {
            AnyStatus()
            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, isDetail: true, theme: themes.theme)
                .padding(10)
                .disabled(true)
                .environmentObject(dim)
                .onReceive(receiveNotification(.iMetaInfoForUrl)) { notification in
                    let (urlString, iMeta) = notification.object as! (String, iMetaInfo)
                    vm.remoteIMetas[urlString] = iMeta
                }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            MediaUploadProgress(uploader: vm.uploader)
                .frame(height: Double(vm.uploader.queued.count * 38))
                .background(themes.theme.background)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized:"Back", comment:"Button to go back")) {
                    dismissPostPreview()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    typingTextModel.sending = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.vm.sendNow(replyTo: replyTo, quotePost: quotePost, onDismiss: {
                            dismissPostPreview()
                            onDismiss()
                        })
                    }
                } label: {
                    if (typingTextModel.uploading || typingTextModel.sending) {
                        ProgressView().colorInvert()
                    }
                    else {
                        Text("Post.verb", comment: "Button to post (publish) a post")
                    }
                }
                .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                .cornerRadius(20)
                .disabled(shouldDisablePostButton)
                .opacity(shouldDisablePostButton ? 0.25 : 1.0)
            }
        }
        .navigationTitle(String(localized: "Post preview", comment: "Navigation title for Post Preview screen"))
        .navigationBarTitleDisplayMode(.inline)
        .background(themes.theme.background)
        .frame(width: dim.listWidth)
        .fixedSize(horizontal: true, vertical: false)
    }
}

func createPreviewEvent(_ event: NEvent) -> Event {
    let context = bg()
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
    previewEvent.isScreenshot = true
            
    if (event.kind == .textNote) {
        // THIS EVENT REPLYING TO SOMETHING
        // CACHE THE REPLY "E" IN replyToId
        if let replyToEtag = event.replyToEtag() {
            previewEvent.replyToId = replyToEtag.id
            
            // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
            if let replyTo = Event.fetchEvent(id: replyToEtag.id, context: context) {
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
                    if let replyToRoot = Event.fetchEvent(id: replyToRootEtag.id, context: context) {
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
    }

    // handle REPOST with normal mentions in .kind 1
    // todo handle first nostr:nevent or not?
    if event.kind == .textNote, let firstE = event.firstMentionETag() {
        previewEvent.firstQuoteId = firstE.id
        // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
        if let firstQuote = Event.fetchEvent(id: previewEvent.firstQuoteId!, context: context) {
            previewEvent.firstQuote = firstQuote
        }
    }
    
    return previewEvent
}

import NavigationBackport

struct PostPreview_Previews: PreviewProvider {
    @StateObject static var vm = NewPostModel()
    @Environment(\.dismiss) static var dismiss
    static var previews: some View {
        PreviewContainer({ pe in
//            pe.loadContacts()
//            pe.loadZaps()
            pe.parseMessages([
                ###"["EVENT", "hashtags", {"id":"026e5287944b34bc4068fcf3882b307d3ba8581f5cd6bc6087142ff2594c4a2a","tags":[["t","nostr"],["t","Nostur"],["t","nostur"],["t","nostriches"],["t","zaps"],["t","bitcoin"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"sig":"ab0a3cfb8c9136f75d650379a2defc2d61c8b54712a88072d174782d622cdd6d90b0fa197b7b9d86ee945e71fd03965a03f53e319a5de073f7397477f8254715","kind":1,"pubkey":"9c33d279c9a48af396cc159c844534e5f38e5d114667748a62fa33ffbc57b653","content":"Trying out some #nostr hashtags for the next update of #Nostur\n\n#nostriches\n\n#zaps  #bitcoin","created_at":1705092290}]"###
            ])
        }) {
            NBNavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost("026e5287944b34bc4068fcf3882b307d3ba8581f5cd6bc6087142ff2594c4a2a") {
                    PostPreview(nrPost: nrPost, replyTo: nil, quotePost: nil, vm: vm, onDismiss: { dismiss() })
                }
            }
        }
    }
}
