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
    }
    
    func onDismiss() {
        privateNote = nil
        post = nil
        contact = nil
    }

}

