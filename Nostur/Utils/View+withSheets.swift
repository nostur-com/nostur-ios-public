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


extension View {
    func withSheets() -> some View {
        modifier(WithSheets())
    }
}

struct WithSheets: ViewModifier {
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    
    // Sheet contents (item based)
    @State private var privateNote: CloudPrivateNote? = nil
    @State private var post: Event? = nil
    @State private var contact: Contact? = nil
//    @State private var fullImage: FullScreenItem? = nil
//    @State private var fullImage17: FullScreenItem17? = nil
    @State private var reportPost: ReportPost? = nil
    @State private var reportContact: ReportContact? = nil
    @State private var addRemoveContactFromList: NRContact? = nil
    @State private var imposterDetails: ImposterDetails? = nil
    
    // Confirmation dialogs
    @State private var restoreContactSheet = false
    @State private var removed: RemovedPubkeys? = nil
    
    @State private var deletePostSheet = false
    @State private var deletePost: DeletePost? = nil
    
    // new post/quote post / new reply
    @State private var replyTo: ReplyTo? = nil
    @State private var quoteOrRepost: QuoteOrRepost? = nil
    @State private var quotePost: QuotePost? = nil
    
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
    
    @StateObject private var screenshotDIM = DIMENSIONS.embeddedDim(availableWidth: min(402, UIScreen.main.bounds.width), isScreenshot: true)
    
    func body(content: Content) -> some View {
        content
            .onReceive(receiveNotification(.editingPrivateNote)) { notification in
                let note = notification.object as! CloudPrivateNote
                self.privateNote = note
            }
            .sheet(item: $privateNote) { note in
                NBNavigationStack {
                    EditPrivateNoteSheet(privateNote: note)
                        .environmentObject(la)
                        .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                post = Event.fetchEvent(id: id, context: viewContext())
            }
            .sheet(item: $post) { post in
                NBNavigationStack {
                    NewPrivateNoteSheet(post: post)
                        .environmentObject(la)
                        .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                contact = Contact.fetchByPubkey(pubkey, context: viewContext())
            }
            .sheet(item: $contact) { contact in
                NBNavigationStack {
                    NewPrivateNoteSheet(contact: contact)
                        .environmentObject(la)
                        .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
            .onReceive(receiveNotification(.reportPost), perform: { notification in
                let post = notification.object as! NRPost
                reportPost = ReportPost(nrPost: post)
            })
            .sheet(item: $reportPost, content: { reportPost in
                NBNavigationStack {
                    ReportPostSheet(nrPost: reportPost.nrPost)
                        .environmentObject(la)
                        .environmentObject(dim)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
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
                        .environmentObject(la)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
                .nbUseNavigationStack(.never)
            })
        
            .onReceive(receiveNotification(.reportContact), perform: { notification in
                reportContact = notification.object as! ReportContact
            })
            .sheet(item: $reportContact, content: { reportContact in
                NBNavigationStack {
                    ReportContactSheet(reportContact: reportContact)
                        .environmentObject(la)
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
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
                        guard let signedDeletion = AccountsState.shared.loggedInAccount?.deletePost(deletePost.eventId) else {
                            return
                        }
                        Unpublisher.shared.publishNow(signedDeletion)
                    }
                }
            })
        
            .onReceive(receiveNotification(.createNewReply)) { notification in
                guard isFullAccount() else { showReadOnlyMessage(); return }
                replyTo = notification.object as? ReplyTo
            }
        
            .onReceive(receiveNotification(.createNewQuoteOrRepost)) { notification in
                guard isFullAccount() else { showReadOnlyMessage(); return }
                quoteOrRepost = notification.object as? QuoteOrRepost
            }
        
            .sheet(item: $replyTo) { replyTo in
                NBNavigationStack {
                    if let account = account(), account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePost(replyTo: replyTo, onDismiss: { self.replyTo = nil })
                                .environmentObject(la)
                                .environmentObject(dim)
                                .environmentObject(themes)
                                .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                    }
                    else {
                        ComposePost(replyTo: replyTo, onDismiss: { self.replyTo = nil })
                            .environmentObject(la)
                            .environmentObject(dim)
                            .environmentObject(themes)
                            .presentationBackgroundCompat(themes.theme.listBackground)
                    }
                }
                .nbUseNavigationStack(.never)
            }
        
            .sheet(item: $quoteOrRepost) { quoteOrRepost in
                if let account = account(), account.isNC {
                    WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                        QuoteOrRepostChoiceSheet(quoteOrRepost: quoteOrRepost, quotePost: $quotePost)
                            .environmentObject(la)
                            .environmentObject(dim)
                            .presentationDetents200()
                            .presentationDragIndicatorVisible()
                            .presentationBackgroundCompat(themes.theme.listBackground)
                    }
                    .environmentObject(themes)
                }
                else {
                    QuoteOrRepostChoiceSheet(quoteOrRepost: quoteOrRepost, quotePost: $quotePost)
                        .environmentObject(la)
                        .environmentObject(dim)
                        .presentationDetents200()
                        .presentationDragIndicatorVisible()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
            }
        
            .sheet(item: $quotePost) { quotePost in
                NBNavigationStack {
                    if let account = account(), account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePost(quotePost: quotePost, onDismiss: { self.quotePost = nil })
                                .environmentObject(la)
                                .environmentObject(dim)
                                .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                        .environmentObject(themes)
                    }
                    else {
                        ComposePost(quotePost: quotePost, onDismiss: { self.quotePost = nil })
                            .environmentObject(la)
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
            .onReceive(receiveNotification(.createNewQuotePost)) { notification in
                let quotePost = notification.object as! QuotePost
                self.quotePost = quotePost
            }
            .sheet(item: $paymentInfo) { paymentInfo in
                PaymentAmountSelector(paymentInfo: paymentInfo)
                    .environmentObject(la)
                    .environmentObject(themes)
                    .presentationBackgroundCompat(themes.theme.listBackground)
            }
        
            .onReceive(receiveNotification(.addRemoveToListsheet)) { notification in
                let contact = notification.object as! NRContact
                addRemoveContactFromList = contact
            }
            .sheet(item: $addRemoveContactFromList) { nrContact in
                NBNavigationStack {
                    AddRemoveToListsheet(nrContact: nrContact)
                        .environmentObject(la)
                        .environmentObject(themes)
                        .environment(\.managedObjectContext, viewContext())
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
                    ComposePost(onDismiss: {
                        self.newHighlight = nil
                    }, kind: .highlight, highlight: newHighlight)
                        .environmentObject(la)
                        .environmentObject(dim)
                        .environmentObject(themes)
                        .environment(\.managedObjectContext, viewContext())
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
                        .presentationDetentsMedium()
                        .environmentObject(la)
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
                        .presentationDetentsLarge()
                        .environmentObject(la)
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
                            // TODO: Fix image size + GIF in screenshot
                            PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != nil && nrPost.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: true, isDetail: true, theme: themes.theme)

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
                                .foregroundColor(themes.theme.listBackground)
                                .shadow(color: Color("ShadowColor").opacity(0.25), radius: 5)
                        )
                        .frame(width: min(402, UIScreen.main.bounds.width))
                        .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        .padding(.vertical, 10)
                        .environmentObject(screenshotDIM)
                        .environmentObject(la)
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

struct ReplyTo: Identifiable {
    let id = UUID()
    let nrPost: NRPost
}

struct QuoteOrRepost: Identifiable {
    let id = UUID()
    let nrPost: NRPost
}

struct QuotePost: Identifiable {
    let id = UUID()
    let nrPost: NRPost
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
    let nrContact: NRContact
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


struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
