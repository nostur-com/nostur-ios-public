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
    
    func existingPrivateNoteBy(pubkey:String) -> PrivateNote? {
            ns.account?
                .privateNotes?
                .first(where: { $0.contact != nil && $0.contact!.pubkey == pubkey })
    }
    
    func existingPrivateNoteBy(id:String) -> PrivateNote? {
            ns.account?
                .privateNotes?
                .first(where: { $0.post != nil && $0.post!.id == id })
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $privateNote) { note in
                EditPrivateNoteSheet(privateNote: note, onDismiss: onDismiss)
            }
            .sheet(item: $post) { post in
                NewPrivateNoteSheet(post: post, onDismiss: onDismiss)
            }
            .sheet(item: $contact) { contact in
                NewPrivateNoteSheet(contact: contact, onDismiss: onDismiss)
            }
            .onReceive(receiveNotification(.editingPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                self.privateNote = existingPrivateNoteBy(pubkey: pubkey)
            }
            .onReceive(receiveNotification(.editingPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                self.privateNote = existingPrivateNoteBy(id: id)
            }
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                let id = notification.object as! String
                post = try! Event.fetchEvent(id: id, context: viewContext)
            }
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                let pubkey = notification.object as! String
                contact = Contact.fetchByPubkey(pubkey, context: viewContext)
            }
    }
    
    func onDismiss() {
        privateNote = nil
        post = nil
        contact = nil
    }

}

