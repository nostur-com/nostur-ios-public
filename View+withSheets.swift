//
//  View+withSheets.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import CoreData

public extension View {
    func withSheets() -> some View {
        modifier(WithSheets())
    }
    
    //    func withSheets(perform action: @escaping () -> Void) -> some View {
    //        modifier(WithSheets())
    //    }
}

private struct WithSheets: ViewModifier {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @State var privateNote:PrivateNote? = nil
    @State var post:Event? = nil
    @State var contact:Contact? = nil
    @State var fullImage:FullScreenItem? = nil
    
    //
    @State var restoreContactSheet = false
    @State var removed:RemovedPubkeys? = nil
    @State var reportPost:ReportPost? = nil
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $fullImage) { f in
                FullImageViewer(fullImageURL: f.url)
            }
            .sheet(item: $privateNote) { note in
                EditPrivateNoteSheet(privateNote: note, onDismiss: onDismiss)
            }
            .sheet(item: $post) { post in
                NewPrivateNoteSheet(post: post, onDismiss: onDismiss)
            }
            .sheet(item: $contact) { contact in
                NewPrivateNoteSheet(contact: contact, onDismiss: onDismiss)
            }
            .sheet(item: $reportPost, content: { reportPost in
                NavigationStack {
                    ReportPostSheet(vPost: reportPost.vPost)
                }
            })
        
            .onReceive(receiveNotification(.reportPost), perform: { notification in
                let post = notification.object as! VPost
                reportPost = ReportPost(vPost: post)
            })
        
        
            .onReceive(receiveNotification(.editingPrivateNote)) { notification in
                let note = notification.object as! PrivateNote
                self.privateNote = note
            }
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                post = try! Event.fetchEvent(id: id, context: viewContext)
            }
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                contact = Contact.fetchByPubkey(pubkey, context: viewContext)
            }
            .onReceive(receiveNotification(.fullScreenView)) { notification in
                let item = notification.object as! FullScreenItem
                fullImage = item
            }
            .onReceive(receiveNotification(.requestConfirmationChangedFollows)) { notification in
                let removed = notification.object as! Set<String>
                self.removed = RemovedPubkeys(pubkeys: removed)
                self.restoreContactSheet = true
            }
            .confirmationDialog("It looks like \(removed?.pubkeys.count ?? 0) contacts were removed from your following list, perhaps from another nostr app", isPresented: $restoreContactSheet, titleVisibility: .visible,  actions: {
                Button("OK", role: .destructive) {
                    guard let removed = self.removed else { return }
                    FollowingGuardian.shared.removeFollowing(removed.pubkeys)
                }
                Button("Restore \(removed?.pubkeys.count ?? 0) contacts", role: .cancel) {
                    FollowingGuardian.shared.restoreFollowing()
                }
                .keyboardShortcut(.defaultAction)
            })
    }
    
    func onDismiss() {
        privateNote = nil
        post = nil
        contact = nil
    }
    
}


struct RemovedPubkeys: Identifiable {
    let pubkeys:Set<String>
    let id = UUID()
}

struct ReportPost: Identifiable {
    let id = UUID()
    let vPost:VPost
}
