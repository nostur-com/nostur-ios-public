//
//  PrivateNoteToggle.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//

import SwiftUI

struct PrivateNoteToggle: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    var post:Event?
    var contact:Contact?
    var existingPrivateNote:PrivateNote? {
        ns.account?
            .privateNotes?
            .filter { ($0.post != nil && $0.post == post) || ($0.contact != nil && $0.contact == contact) }
            .first
    }
    var postHasPrivateNote:Bool {
        (ns.account?
            .privateNotes?
            .filter { ($0.post != nil && $0.post == post) || ($0.contact != nil && $0.contact == contact) }
            .count ?? 0) != 0
    }
    
    var body: some View {
        HStack {
            Button {
                if let existingPrivateNote {
                    sendNotification(.editingPrivateNote, existingPrivateNote)
                }
                else {
                    if let post {
                        sendNotification(.newPrivateNoteOnPost, post)
                    }
                    if let contact {
                        sendNotification(.newPrivateNoteOnContact, contact)
                    }
                }
            } label: {
                Image(systemName: "note.text")
            }
            .opacity(postHasPrivateNote ? 1 : 0.2)
        }
        
    }
}

struct PrivateNoteToggle_Previews: PreviewProvider {
    static var previews: some View {
        let post = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        if (post != nil) {
            PrivateNoteToggle(post: post!)
                .withPreviewEnvironment()
        }
    }
}
