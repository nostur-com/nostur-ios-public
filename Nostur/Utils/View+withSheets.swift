import SwiftUI
import CoreData

public extension View {
    func withSheets() -> some View {
        modifier(WithSheets())
    }
}

private struct WithSheets: ViewModifier {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    
    // Sheet contents (item based)
    @State var privateNote:PrivateNote? = nil
    @State var post:Event? = nil
    @State var contact:Contact? = nil
    @State var fullImage:FullScreenItem? = nil
    @State var reportPost:ReportPost? = nil
    @State var reportContact:ReportContact? = nil
    @State var addRemoveContactFromList:Contact? = nil
    
    // Confirmation dialogs
    @State var restoreContactSheet = false
    @State var removed:RemovedPubkeys? = nil
    
    @State var deletePostSheet = false
    @State var deletePost:DeletePost? = nil
    
    // new post/quote post / new reply
    @State var replyToEvent:Event? = nil
    @State var quoteOrRepostEvent:Event? = nil
    @State var quotePostEvent:Event? = nil
    
    // Zap sheet
    @State var paymentInfo:PaymentInfo? = nil
    
    // New highlight sheet
    @State var newHighlight:NewHighlight? = nil
    
    @State var contextMenuNrPost:NRPost? = nil
    
    func body(content: Content) -> some View {
        content
            .onReceive(receiveNotification(.fullScreenView)) { notification in
                let item = notification.object as! FullScreenItem
                fullImage = item
            }
            .fullScreenCover(item: $fullImage) { f in
                FullImageViewer(fullImageURL: f.url)
            }
        
            .onReceive(receiveNotification(.editingPrivateNote)) { notification in
                let note = notification.object as! PrivateNote
                self.privateNote = note
            }
            .sheet(item: $privateNote) { note in
                EditPrivateNoteSheet(privateNote: note)
            }
           
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                post = try! Event.fetchEvent(id: id, context: viewContext)
            }
            .sheet(item: $post) { post in
                NewPrivateNoteSheet(post: post)
            }
             
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                contact = Contact.fetchByPubkey(pubkey, context: viewContext)
            }
            .sheet(item: $contact) { contact in
                NewPrivateNoteSheet(contact: contact)
            }
        
            .onReceive(receiveNotification(.reportPost), perform: { notification in
                let post = notification.object as! NRPost
                reportPost = ReportPost(nrPost: post)
            })
            .sheet(item: $reportPost, content: { reportPost in
                NavigationStack {
                    ReportPostSheet(nrPost: reportPost.nrPost)
                        .environmentObject(dim)
                        .environmentObject(ns)
                }
            })
        
            .onReceive(receiveNotification(.reportContact), perform: { notification in
                let contact = notification.object as! Contact
                reportContact = ReportContact(contact: contact)
            })
            .sheet(item: $reportContact, content: { reportContact in
                NavigationStack {
                    ReportContactSheet(contact: reportContact.contact)
                }
            })
            
            .onReceive(receiveNotification(.requestConfirmationChangedFollows)) { notification in
                let removed = notification.object as! Set<String>
                self.removed = RemovedPubkeys(pubkeys: removed)
                self.restoreContactSheet = true
            }
            .confirmationDialog("It looks like \(removed?.pubkeys.count ?? 0) contacts were removed from your following list, perhaps from another nostr app", isPresented: $restoreContactSheet, titleVisibility: .visible,  actions: {
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
                    guard let deletePost = self.deletePost else { return }
                    guard let signedDeletion = NosturState.shared.deletePost(deletePost.eventId) else {
                        return
                    }
                    Unpublisher.shared.publishNow(signedDeletion)
                }
            })
        
            .onReceive(receiveNotification(.createNewReply)) { notification in
                guard ns.account?.privateKey != nil else {
                    ns.readOnlyAccountSheetShown = true
                    return
                }
                replyToEvent = notification.object as? Event
            }
                       
            .onReceive(receiveNotification(.createNewQuoteOrRepost)) { notification in
                guard ns.account?.privateKey != nil else {
                    ns.readOnlyAccountSheetShown = true
                    return
                }
                quoteOrRepostEvent = notification.object as? Event
            }
        
            .sheet(item: $replyToEvent) { event in
                NavigationStack {
                    NewReply(replyTo: event)
                        .environmentObject(ns)
                        .environmentObject(dim)
                }
            }
        
            .sheet(item: $quoteOrRepostEvent) { event in
                QuoteOrRepostChoiceSheet(originalEvent:event, quotePostEvent:$quotePostEvent)
                    .environmentObject(ns)
                    .environmentObject(dim)
                    .presentationDetents([.height(200)])
                    .presentationDragIndicator(.visible)
            }
        
            .sheet(item: $quotePostEvent) { quotePostEvent in
                NavigationStack {
                    NewQuoteRepost(quotingEvent: quotePostEvent)
                        .environmentObject(ns)
                        .environmentObject(dim)
                }
            }
        
            .onReceive(receiveNotification(.showZapSheet)) { notification in
                let paymentInfo = notification.object as! PaymentInfo
                self.paymentInfo = paymentInfo
            }
            .sheet(item: $paymentInfo) { paymentInfo in
                PaymentAmountSelector(paymentInfo:paymentInfo)
            }
        
            .onReceive(receiveNotification(.addRemoveToListsheet)) { notification in
                let contact = notification.object as! Contact
                addRemoveContactFromList = contact
            }
            .sheet(item: $addRemoveContactFromList) { contact in
                AddRemoveToListsheet(contact: contact)
            }

            // New highlight
            .onReceive(receiveNotification(.newHighlight)) { notification in
                let newHighlight = notification.object as! NewHighlight
                self.newHighlight = newHighlight
            }
            .sheet(item: $newHighlight) { newHighlight in
                NavigationStack {
                    HighlightComposer(highlight: newHighlight)
                        .environmentObject(ns)
                }
            }
        
            // Lazy note context menu (because Menu() on every post is slow???)
            .onReceive(receiveNotification(.showNoteMenu)) { notification in
                let nrPost = notification.object as! NRPost
                self.contextMenuNrPost = nrPost
            }
            .sheet(item: $contextMenuNrPost) { nrPost in
                LazyNoteMenuSheet(nrPost: nrPost)
                    .environmentObject(ns)
                    .presentationDetents([.medium])
            }
    }
}


struct RemovedPubkeys: Identifiable {
    let pubkeys:Set<String>
    let id = UUID()
}

struct ReportPost: Identifiable {
    let id = UUID()
    let nrPost:NRPost
}

struct ReportContact: Identifiable {
    let id = UUID()
    let contact:Contact
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
