//
//  PrivateNoteToggle.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//

import SwiftUI

struct ContactPrivateNoteToggle: View {
    @ObservedObject var contact:Contact
    
    var body: some View {
        HStack {
            Button {
                if contact.hasPrivateNote {
                    sendNotification(.editingPrivateNoteOnContact, contact.pubkey)
                }
                else {
                    sendNotification(.newPrivateNoteOnContact, contact.pubkey)
                }
            } label: {
                Image(systemName: "note.text")
                    .padding(5)
            }
            .opacity(contact.hasPrivateNote ? 1 : 0.2)
        }
    }
}

struct EventPrivateNoteToggle: View {
    @ObservedObject var event:Event

    var body: some View {
        HStack {
            Button {
                if event.hasPrivateNote {
                    sendNotification(.editingPrivateNoteOnPost, event.id)
                }
                else {
                    sendNotification(.newPrivateNoteOnPost, event.id)
                }
            } label: {
                Image(systemName: "note.text")
                    .padding(5)
            }
            .opacity(event.hasPrivateNote ? 1 : 0.2)
        }
    }
}


//struct PrivateNoteToggle_Previews: PreviewProvider {
//    static var previews: some View {
//        let post = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
//        if (post != nil) {
//            PrivateNoteToggle(vPost: post)
//                .withPreviewEnvironment()
//        }
//    }
//}
