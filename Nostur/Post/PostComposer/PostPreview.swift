//
//  PostPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/04/2023.
//

import SwiftUI
import NostrEssentials

struct PostPreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth

    public let nrPost: NRPost
    public let kind: NEventKind
    public let replyTo: ReplyTo?
    public let quotePost: QuotePost?
    @ObservedObject public var vm: NewPostModel
    @ObservedObject public var typingTextModel: TypingTextModel
    public let onDismiss: () -> Void
    @State private var postPreviewWidth: CGFloat? = nil

    // This previewEvent is not saved in database
    // Code is basically from Event.saveEvent, without unnecessary bits
    
    init(nrPost: NRPost, kind: NEventKind = .textNote, replyTo: ReplyTo?, quotePost: QuotePost?, vm: NewPostModel, onDismiss: @escaping () -> Void) {
        self.nrPost = nrPost
        self.kind = kind
        self.replyTo = replyTo
        self.quotePost = quotePost
        self.vm = vm
        self.onDismiss = onDismiss
        self.typingTextModel = vm.typingTextModel
    }
    
    private var shouldDisablePostButton: Bool {
        if (kind == .picture && typingTextModel.pastedImages.isEmpty) { return true }
            
        if (typingTextModel.sending || typingTextModel.uploading) { return true }
        
        if kind == .highlight { return false }
        
        if (typingTextModel.text.isEmpty && typingTextModel.pastedImages.isEmpty && typingTextModel.pastedVideos.isEmpty) { return true }
            
        return false
    }

    var body: some View {
        ScrollView {
            AnyStatus()
            PostRowDeletable(nrPost: nrPost, missingReplyTo: true, isDetail: true, theme: theme)
                .environment(\.nxViewingContext, [.preview, .postDetail])
                .padding(10)
                .disabled(true)
                .onReceive(receiveNotification(.iMetaInfoForUrl)) { notification in
                    let (urlString, iMeta) = notification.object as! (String, iMetaInfo)
                    vm.remoteIMetas[urlString] = iMeta
                }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            MediaUploadProgress(uploader: vm.uploader) // @TODO: Make progress independent of Uploader type (NIP96 / Blossom)
                .frame(height: Double(vm.uploader.queued.count * 38))
                .background(theme.listBackground)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    typingTextModel.sending = true
                    
                    // Need to do these here in main thread
                    guard let account = vm.activeAccount, account.isFullAccount else {
                        sendNotification(.anyStatus, ("Problem with account", "NewPost"))
                        return
                    }
                    let isNC = account.isNC
                    let pubkey = account.publicKey
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // crash if we don't delay
                        Task {
                            await self.vm.sendNow(isNC: isNC, pubkey: pubkey, account: account, replyTo: replyTo, quotePost: quotePost, onDismiss: {
                                onDismiss()
                            })
                        }
                    }
                } label: {
                    if (typingTextModel.uploading || typingTextModel.sending) {
                        ProgressView().colorInvert()
                    }
                    else {
                        Label(String(localized: "Post.verb", comment: "Button to post (publish) a post"), systemImage: "paperplane.fill")
                    }
                }
                .buttonStyleGlassProminent()
                .disabled(shouldDisablePostButton)
                .opacity(shouldDisablePostButton ? 0.25 : 1.0)
                .help("Send")
            }
        }
        .navigationTitle(String(localized: "Preview", comment: "Navigation title for Post Preview screen"))
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.listBackground)
        .frame(width: availableWidth)
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
    previewEvent.pubkey = event.publicKey
    previewEvent.likesCount = 0
    previewEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
            
    if (event.kind == .textNote || event.kind == .comment) {
        // THIS EVENT REPLYING TO SOMETHING
        // CACHE THE REPLY "E" IN replyToId
        if let replyToEtag = event.replyToEtag() {
            previewEvent.replyToId = replyToEtag.id
        }
        
        // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO
        // DO THE SAME AS WITH THE REPLY BEFORE
        if let replyToRootEtag = event.replyToRootEtag() {
            if (replyToRootEtag.id != previewEvent.replyToId) { // If reply root is same as reply, dont double add.
                previewEvent.replyToRootId = replyToRootEtag.id
                if (previewEvent.replyToId == nil) { // IF IT HAS ONLY A ROOT REPLY, NO NORMAL REPLY: THEN REPLYTOROOT = REPLYTO
                    previewEvent.replyToId = replyToRootEtag.id
                }
            }
        }
    }

    // handle REPOST with normal mentions in .kind 1
    // todo handle first nostr:nevent or not?
    if event.kind == .textNote, let firstE = event.firstMentionETag() {
        previewEvent.firstQuoteId = firstE.id
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
                    PostPreview(nrPost: nrPost, kind: .textNote, replyTo: nil, quotePost: nil, vm: vm, onDismiss: { dismiss() })
                }
            }
        }
    }
}
