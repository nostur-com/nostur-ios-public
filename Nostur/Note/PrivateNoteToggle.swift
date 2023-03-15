//
//  PrivateNoteToggle.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//

import SwiftUI

struct PrivateNoteToggle: View {
    let vPost:VPost?
    let vContact:VContact?
    
    init(vPost: VPost? = nil, vContact: VContact? = nil) {
        self.vPost = vPost
        self.vContact = vContact
    }
    
    var body: some View {
        if let vPost {
            HStack {
                Button {
                    if vPost.hasPrivateNote {
                        sendNotification(.editingPrivateNoteOnPost, vPost.id)
                    }
                    else {
                        sendNotification(.newPrivateNoteOnPost, vPost.id)
                    }
                } label: {
                    Image(systemName: "note.text")
                        .padding(5)
                }
                .opacity(vPost.hasPrivateNote ? 1 : 0.2)
            }
        }
        else if let vContact {
            HStack {
                Button {
                    if vContact.hasPrivateNote {
                        sendNotification(.editingPrivateNoteOnContact, vContact.pubkey)
                    }
                    else {
                        sendNotification(.newPrivateNoteOnContact, vContact.pubkey)
                    }
                } label: {
                    Image(systemName: "note.text")
                        .padding(5)
                }
                .opacity(vContact.hasPrivateNote ? 1 : 0.2)
            }
        }
    }
}

struct PrivateNoteToggle_Previews: PreviewProvider {
    static var previews: some View {
        let post = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        if (post != nil) {
            PrivateNoteToggle(vPost: post)
                .withPreviewEnvironment()
        }
    }
}
