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
                if let pn = contact.privateNote {
                    sendNotification(.editingPrivateNote, pn)
                }
                else {
                    sendNotification(.newPrivateNoteOnContact, contact.pubkey)
                }
            } label: {
                Image(systemName: "note.text")
                    .padding(5)
            }
            .opacity(contact.privateNote != nil ? 1 : 0.2)
        }
    }
}

struct EventPrivateNoteToggle: View {
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
    }
    
    var body: some View {
        Image(systemName: "note.text")
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
            .opacity(footerAttributes.hasPrivateNote ? 1 : 0.2)
            .onTapGesture {
                if let pn = nrPost.mainEvent.privateNote {
                    sendNotification(.editingPrivateNote, pn)
                }
                else {
                    sendNotification(.newPrivateNoteOnPost, nrPost.id)
                }
            }
    }
}


struct PrivateNoteToggle_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            NavigationStack {
                if let post = PreviewFetcher.fetchNRPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3") {
                    EventPrivateNoteToggle(nrPost: post)
                }
            }
        }
    }
}
