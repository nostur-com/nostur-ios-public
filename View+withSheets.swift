//
//  View+withSheets.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

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
            .onReceive(receiveNotification(.editingPrivateNote)) { notification in
                let privateNote = notification.object as! PrivateNote
                self.privateNote = privateNote
            }
            .onReceive(receiveNotification(.newPrivateNoteOnPost)) { notification in
                post = notification.object as? Event
            }
            .onReceive(receiveNotification(.newPrivateNoteOnContact)) { notification in
                contact = notification.object as? Contact
            }
    }
    
    func onDismiss() {
        privateNote = nil
        post = nil
        contact = nil
    }

}

