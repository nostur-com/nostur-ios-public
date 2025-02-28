//
//  View+withSheets.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import CoreData
import UIKit
import Combine
import NavigationBackport


public extension View {
    func withSheets() -> some View {
        modifier(WithSheets())
    }
}

private struct WithSheets: ViewModifier {
    @EnvironmentObject private var themes: Themes
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var dim: DIMENSIONS
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    
    // Sheet contents (item based)
    @State private var privateNote: CloudPrivateNote? = nil
    @State private var post: Event? = nil
    @State private var contact: Contact? = nil
    @State private var fullImage: FullScreenItem? = nil
    @State private var fullImage17: FullScreenItem17? = nil
    @State private var reportPost: ReportPost? = nil
    @State private var reportContact: ReportContact? = nil
    @State private var addRemoveContactFromList: Contact? = nil
    @State private var imposterDetails: ImposterDetails? = nil
    
    // Confirmation dialogs
    @State private var restoreContactSheet = false
    @State private var removed: RemovedPubkeys? = nil
    
    @State private var deletePostSheet = false
    @State private var deletePost: DeletePost? = nil
    
    // new post/quote post / new reply
    @State private var replyToEvent: EventNotification? = nil
    @State private var quoteOrRepostEvent: Event? = nil
    @State private var quotePostEvent: Event? = nil
    
    // Zap sheet
    @State private var paymentInfo: PaymentInfo? = nil
    
    // New highlight sheet
    @State private var newHighlight: NewHighlight? = nil
    
    @State private var contextMenuNrPost: NRPost? = nil
    @State private var zapCustomizerSheetInfo: ZapCustomizerSheetInfo? = nil
    
    // Share post screenshot
    @State private var sharablePostImage: ShareablePostImage? = nil
    @State private var screenshotRenderer: AnyCancellable? = nil
    //    @State private var renderer:ImageRenderer<AnyView>? = nil
    @State private var shareableWeblink: ShareableWeblink? = nil
    
    @State private var miniProfileSheetInfo: MiniProfileSheetInfo? = nil
    @State private var miniProfileAnimateIn = false
    @State private var mediaPostPreview = true
    @State private var sharableImage: UIImage? = nil
    @State private var sharableGif: Data? = nil
    
    @StateObject private var screenshotDIM = DIMENSIONS.embeddedDim(availableWidth: 600, isScreenshot: true)
    
    func body(content: Content) -> some View {
        content
            .onReceive(receiveNotification(.fullScreenView)) { notification in
                let item = notification.object as! FullScreenItem
                fullImage = item
            }
            .fullScreenCover(item: $fullImage) { f in
                NBNavigationStack {
                    FullImageViewer(fullImageURL: f.url, galleryItem: f.galleryItem, mediaPostPreview: $mediaPostPreview, sharableImage: $sharableImage, sharableGif: $sharableGif)
                        .environmentObject(themes)
                        .environmentObject(dim)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                        .onAppear(perform: {
                            sharableImage = nil
                            sharableGif = nil
                        })
                        .onDisappear(perform: {
                            sharableImage = nil
                            sharableGif = nil
                        })
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close", systemImage: "multiply") {
                                    fullImage = nil
                                    dismiss()
                                }
                                .font(.title2)
                                .buttonStyle(.borderless)
                                .foregroundColor(themes.theme.accent)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                if let sharableImage {
                                    ShareMediaButton(sharableImage: sharableImage)
                                }
                                else if let sharableGif {
                                    ShareGifButton(sharableGif: sharableGif)
                                }
                            }
                        }
                }
                .nbUseNavigationStack(.never)
            }
            .onReceive(receiveNotification(.fullScreenView17)) { notification in
                let item = notification.object as! FullScreenItem17
                fullImage17 = item
            }
            .fullScreenCover(item: $fullImage17) { f in
                NBNavigationStack {
                    GalleryFullScreenSwiper(initialIndex: f.index, items: f.items)
                        .environmentObject(themes)
                        .environmentObject(dim)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
            .onReceive(receiveNotification(.editingPrivateNote)) { notification in
                let note = notification.object as! CloudPrivateNote
                self.privateNote = note
            }
            .sheet(item: $privateNote) { note in
                NBNavigationStack {
                    EditPrivateNoteSheet(privateNote: note)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                post = try! Event.fetchEvent(id: id, context: viewContext)
            }
            .sheet(item: $post) { post in
                NBNavigationStack {
                    NewPrivateNoteSheet(post: post)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                contact = Contact.fetchByPubkey(pubkey, context: viewContext)
            }
            .sheet(item: $contact) { contact in
                NBNavigationStack {
                    NewPrivateNoteSheet(contact: contact)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
            .onReceive(receiveNotification(.reportPost), perform: { notification in
                let post = notification.object as! NRPost
                reportPost = ReportPost(nrPost: post)
            })
            .sheet(item: $reportPost, content: { reportPost in
                NBNavigationStack {
                    ReportPostSheet(nrPost: reportPost.nrPost)
                        .environmentObject(dim)
                        .environmentObject(NRState.shared)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.background)
                }
                .nbUseNavigationStack(.never)
            })
        
            .onReceive(receiveNotification(.showImposterDetails), perform: { notification in
                let imposterDetails = notification.object as! ImposterDetails
                self.imposterDetails = imposterDetails
            })
            .sheet(item: $imposterDetails, content: { imposterDetails in
                NBNavigationStack {
                    PossibleImposterDetail(possibleImposterPubkey: imposterDetails.pubkey, followingPubkey: imposterDetails.similarToPubkey)
                        .environmentObject(NRState.shared)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.background)
                }
                .nbUseNavigationStack(.never)
            })
        
            .onReceive(receiveNotification(.reportContact), perform: { notification in
                let contact = notification.object as! Contact
                reportContact = ReportContact(contact: contact)
            })
            .sheet(item: $reportContact, content: { reportContact in
                NBNavigationStack {
                    ReportContactSheet(contact: reportContact.contact)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.background)
                }
                .nbUseNavigationStack(.never)
            })
        
            .onReceive(receiveNotification(.requestConfirmationChangedFollows)) { notification in
                let removed = notification.object as! RemovedPubkeys
                self.removed = removed
                self.restoreContactSheet = true
            }
            .confirmationDialog("It looks like \(removed?.pubkeys.count ?? 0) contacts were removed from your following list, perhaps from another nostr app\(removed?.namesString != nil ? ": \(removed?.namesString ?? "")" : "")", isPresented: $restoreContactSheet, titleVisibility: .visible,  actions: {
                Button("Remove \(removed?.pubkeys.count ?? 0) contacts", role: .destructive) {
                    guard let removed = self.removed else { return }
                    FollowingGuardian.shared.removeFollowing(removed.pubkeys)
                }
                Button("Restore \(removed?.pubkeys.count ?? 0) contacts") {
                    FollowingGuardian.shared.restoreFollowing(removed:removed?.pubkeys ?? [])
                }
                Button("Ignore", role: .cancel) {
                    FollowingGuardian.shared.restoreFollowing(removed:removed?.pubkeys ?? [], republish: false)
                }
                .keyboardShortcut(.defaultAction)
            })
        
            .onReceive(receiveNotification(.requestDeletePost)) { notification in
                let eventId = notification.object as! String
                self.deletePost = DeletePost(eventId: eventId)
                self.deletePostSheet = true
            }
            .confirmationDialog("It's up to relays and other apps to honor your request", isPresented: $deletePostSheet, titleVisibility: .visible,  actions: {
                Button("Request delete", role: .destructive) {
                    guard let account = account() else { return }
                    guard let deletePost = self.deletePost else { return }
                    
                    if account.isNC {
                        var deletion = EventMessageBuilder.makeDeleteEvent(eventId: deletePost.eventId)
                        deletion.publicKey = account.publicKey
                        deletion = deletion.withId()
                        
                        NSecBunkerManager.shared.requestSignature(forEvent: deletion, usingAccount: account, whenSigned: { signedEvent in
                            Unpublisher.shared.publishNow(signedEvent)
                        })
                    }
                    else {
                        guard let signedDeletion = NRState.shared.loggedInAccount?.deletePost(deletePost.eventId) else {
                            return
                        }
                        Unpublisher.shared.publishNow(signedDeletion)
                    }
                }
            })
        
            .onReceive(receiveNotification(.createNewReply)) { notification in
                guard isFullAccount() else { showReadOnlyMessage(); return }
                replyToEvent = notification.object as? EventNotification
            }
        
            .onReceive(receiveNotification(.createNewQuoteOrRepost)) { notification in
                guard isFullAccount() else { showReadOnlyMessage(); return }
                quoteOrRepostEvent = notification.object as? Event
            }
        
            .sheet(item: $replyToEvent) { eventNotification in
                NBNavigationStack {
                    if let account = account(), account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePostCompat(replyTo: eventNotification.event, onDismiss: { self.replyToEvent = nil })
                                .environmentObject(NRState.shared)
                                .environmentObject(dim)
                                .environmentObject(themes)
                                .presentationBackgroundCompat(themes.theme.background)
                        }
                    }
                    else {
                        ComposePostCompat(replyTo: eventNotification.event, onDismiss: { self.replyToEvent = nil })
                            .environmentObject(NRState.shared)
                            .environmentObject(dim)
                            .environmentObject(themes)
                            .presentationBackgroundCompat(themes.theme.background)
                    }
                }
                .nbUseNavigationStack(.never)
            }
        
            .sheet(item: $quoteOrRepostEvent) { event in
                if let account = account(), account.isNC {
                    WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                        QuoteOrRepostChoiceSheet(originalEvent:event, quotePostEvent:$quotePostEvent)
                            .environmentObject(NRState.shared)
                            .environmentObject(dim)
                            .presentationDetents200()
                            .presentationDragIndicatorVisible()
                            .presentationBackgroundCompat(themes.theme.listBackground)
                    }
                    .environmentObject(themes)
                }
                else {
                    QuoteOrRepostChoiceSheet(originalEvent:event, quotePostEvent:$quotePostEvent)
                        .environmentObject(NRState.shared)
                        .environmentObject(dim)
                        .presentationDetents200()
                        .presentationDragIndicatorVisible()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
            }
        
            .sheet(item: $quotePostEvent) { quotePostEvent in
                NBNavigationStack {
                    if let account = account(), account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePostCompat(quotingEvent: quotePostEvent, onDismiss: { self.quotePostEvent = nil })
                                .environmentObject(NRState.shared)
                                .environmentObject(dim)
                                .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                        .environmentObject(themes)
                    }
                    else {
                        ComposePostCompat(quotingEvent: quotePostEvent, onDismiss: { self.quotePostEvent = nil })
                            .environmentObject(NRState.shared)
                            .environmentObject(dim)
                            .environmentObject(themes)
                            .presentationBackgroundCompat(themes.theme.listBackground)
                    }
                }
                .nbUseNavigationStack(.never)
            }
        
            .onReceive(receiveNotification(.showZapSheet)) { notification in
                let paymentInfo = notification.object as! PaymentInfo
                guard paymentInfo.zapAtag == nil else { return } // handle aTag in LiveEventDetail for now
                self.paymentInfo = paymentInfo
            }
            .sheet(item: $paymentInfo) { paymentInfo in
                PaymentAmountSelector(paymentInfo: paymentInfo)
                    .environmentObject(themes)
                    .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
            .onReceive(receiveNotification(.addRemoveToListsheet)) { notification in
                let contact = notification.object as! Contact
                addRemoveContactFromList = contact
            }
            .sheet(item: $addRemoveContactFromList) { contact in
                NBNavigationStack {
                    AddRemoveToListsheet(contact: contact)
                        .environmentObject(themes)
                        .environment(\.managedObjectContext, viewContext)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
        // New highlight
            .onReceive(receiveNotification(.newHighlight)) { notification in
                let newHighlight = notification.object as! NewHighlight
                self.newHighlight = newHighlight
            }
            .sheet(item: $newHighlight) { newHighlight in
                NBNavigationStack {
                    HighlightComposer(highlight: newHighlight)
                        .environmentObject(NRState.shared)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
        // Lazy note context menu (because Menu() on every post is slow???)
            .onReceive(receiveNotification(.showNoteMenu)) { notification in
                let nrPost = notification.object as! NRPost
                self.contextMenuNrPost = nrPost
            }
            .sheet(item: $contextMenuNrPost) { nrPost in
                NBNavigationStack {
                    LazyNoteMenuSheet(nrPost: nrPost)
                        .environmentObject(NRState.shared)
                        .presentationDetentsMedium()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            }
        
        // Zap customizer sheet
            .onReceive(receiveNotification(.showZapCustomizerSheet)) { notification in
                let zapCustomizerSheetInfo = notification.object as! ZapCustomizerSheetInfo
                guard zapCustomizerSheetInfo.zapAtag == nil else { return } // handled in LiveEventDetail for now
                self.zapCustomizerSheetInfo = zapCustomizerSheetInfo
            }
            .sheet(item: $zapCustomizerSheetInfo) { zapCustomizerSheetInfo in
                    ZapCustomizerSheet(name: zapCustomizerSheetInfo.name, customZapId: zapCustomizerSheetInfo.customZapId, supportsZap: true)
                        .environmentObject(NRState.shared)
                        .presentationDetentsLarge()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
        // Share post screenshot
            .onReceive(receiveNotification(.sharePostScreenshot)) { notification in
                if #available(iOS 16.0, *) {
                
                    // TODO: Disabled for now, for some reason even after requesting permissions
                    // we still don't get the "Save to Photos" option
                    // Request write access to the user's photo library.
    //                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
    //                    L.og.debug("Requested access to write screenshot to photo library")
    //                    // don't care if allowed or denied, will just show 1 less option in share sheet if denied
    //                    // (Save to Photos)
    //
    //                }
                    
                    
                    let nrPost = notification.object as! NRPost
                    nrPost.isScreenshot = true // Will hide 'Sent to X relays' in footer + Use Text instead of NRText
                    
                    let renderer = ImageRenderer(content:
                        VStack(spacing:0) {
                            DetailPost(nrPost: nrPost)
                            Group {
                                if SettingsStore.shared.includeSharedFrom {
                                    Text("Shared from **Nostur**")
                                    Text("A nostr client for iOS & macOS - nostur.com")
                                        .padding(.bottom, 5)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
    //                        .padding(.trailing, 10)
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(Color.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10.0)
                                .foregroundColor(themes.theme.background)
                                .shadow(color: Color("ShadowColor").opacity(0.25), radius: 5)
                        )
                        .frame(width: 600)
                        .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        .padding(.vertical, 10)
                        .environmentObject(screenshotDIM)
                        .environmentObject(NRState.shared)
                        .environment(\.managedObjectContext, DataProvider.shared().viewContext)
                        .environment(\.colorScheme, colorScheme)
                        .environmentObject(themes)
                    )
                    
                    
                    renderer.scale = 2.0
                    
                    // First render:
                    guard renderer.uiImage != nil else { return }
                    
                    // We need another render after any async stuff is loaded (inline quotes, images...)
                    screenshotRenderer = renderer.objectWillChange
                        .debounce(for: 0.35, scheduler: RunLoop.main)
                        .sink {
                            guard let uiImage = renderer.uiImage else { return }
                            
                            // Trigger the share sheet
                            self.sharablePostImage = ShareablePostImage(image: uiImage, title: "Screenshot", subtitle: "Screenshot")
                            screenshotRenderer = nil
                        }
                }
                
            }
            .sheet(item: $sharablePostImage) { sharablePostImage in
                ActivityView(activityItems: [sharablePostImage])
            }
        
        // Share post weblink
            .onReceive(receiveNotification(.shareWeblink)) { notification in
                let nrPost = notification.object as! NRPost
                
                let relays = Array(nrPost.footerAttributes.relays).map { String($0) }
                    .filter {
                        // don't inculude localhost / 127.0.x.x / ws:// (non-wss)
                        !$0.contains("/localhost") && !$0.contains("ws:/") && !$0.contains("s:/127.0") && $0 != "local" && $0 != "iCloud"
                    }
                    .map { relay in
                        // first try to put just scheme+hostname as relay. because extra parameters in url can be irrelevant
                        if let url = URL(string: relay), let scheme = url.scheme, let host = url.host {
                            return (scheme + "://" + host)
                        }
                        else {
                            return relay
                        }
                    }
                
                if nrPost.kind == 30023 {
                    guard let sharable = try? ShareableIdentifier(prefix: "naddr", kind: nrPost.kind, pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: relays) else { return }
                    let url = "https://njump.me/\(sharable.bech32string)"
                    self.shareableWeblink = ShareableWeblink(url: url)
                }
                else {
                    guard let sharable = try? ShareableIdentifier(prefix: "nevent", kind: nrPost.kind, pubkey: nrPost.pubkey, eventId: nrPost.id, relays: relays) else { return }
                    let url = "https://njump.me/\(sharable.bech32string)"
                    self.shareableWeblink = ShareableWeblink(url: url)
                }
            }
            .sheet(item: $shareableWeblink) { shareableWeblink in
                ActivityView(activityItems: [NSURL(string: shareableWeblink.url)!])
            }
        
            .onReceive(receiveNotification(.showMiniProfile)) { notification in
                let miniProfileSheetInfo = notification.object as! MiniProfileSheetInfo
                self.miniProfileSheetInfo = miniProfileSheetInfo
            }
        
            .overlay(alignment:.topLeading) {
                if let m = miniProfileSheetInfo {
                    ZStack(alignment:.topLeading) {
                        Rectangle()
                            .fill(.thinMaterial)
                            .opacity(0.8)
                            .zIndex(50)
                            .onTapGesture {
                                miniProfileSheetInfo = nil
                            }
                            .onAppear {
                                miniProfileAnimateIn = true
                            }
                        ProfileOverlayCardContainer(pubkey: m.pubkey, contact: m.contact, zapEtag: m.zapEtag)
                            .scaleEffect(miniProfileAnimateIn ? 1.0 : 0.25, anchor: .leading)
                            .opacity(miniProfileAnimateIn ? 1.0 : 0.15)
                            .animation(.easeInOut(duration: 0.15), value: miniProfileAnimateIn)
                            .offset(x: 0.0, y: min(max(m.location.y - 60,50), UIScreen.main.bounds.height - 350))
                            .zIndex(50)
                    }
                    .onDisappear {
                        miniProfileAnimateIn = false
                    }
                    .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                        miniProfileSheetInfo = nil
                    }
                }
            }
    }
}

struct MiniProfileSheetInfo: Identifiable, Equatable {
    let id = UUID()
    let pubkey: String
    var contact: NRContact?
    var zapEtag: String? = nil
    let location: CGPoint
    
    static func == (lhs: MiniProfileSheetInfo, rhs: MiniProfileSheetInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct EventNotification: Identifiable {
    let id = UUID()
    let event:Event // bg
}

import LinkPresentation
import UniformTypeIdentifiers

final class ShareablePostImage: NSObject, UIActivityItemSource, Identifiable {
    let id = UUID()
    private let image: UIImage
    private var pngData: Data?
    private let title: String
    private let subtitle: String?
    
    init(image: UIImage, title: String, subtitle: String? = nil) {
        self.image = image
        self.pngData = image.pngData()
        self.title = title
        self.subtitle = subtitle
        
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if pngData != nil {
            return pngData
        }
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if pngData != nil {
            return UTType.png.identifier
        }
        return UTType.jpeg.identifier
    }
    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        
        metadata.iconProvider = NSItemProvider(object: self.image)
        metadata.title = title
        if let subtitle = subtitle {
            metadata.originalURL = URL(fileURLWithPath: subtitle)
        }
        
        return metadata
    }
}

struct ShareableWeblink: Identifiable {
    let id = UUID()
    let url:String
}

struct RemovedPubkeys: Identifiable {
    let pubkeys:Set<String>
    let id = UUID()
    var namesString: String?
}

struct ReportPost: Identifiable {
    let id = UUID()
    let nrPost:NRPost
}

struct ReportContact: Identifiable {
    let id = UUID()
    let contact:Contact
}

struct ImposterDetails: Identifiable {
    var id: String { pubkey }
    public let pubkey: String
    public var similarToPubkey: String?
}



struct DeletePost: Identifiable {
    let id = UUID()
    let eventId:String
}

struct NewHighlight: Identifiable {
    let id = UUID()
    let url:String
    let selectedText:String
    var title:String? = nil
}

struct Previews_View_withSheets_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack {
                Button("Test") {
                    sendNotification(
                        .requestConfirmationChangedFollows,
                        Set(["dede","dededed"])
                    )
                }
                Color.clear.withSheets()
            }
        }
    }
}
