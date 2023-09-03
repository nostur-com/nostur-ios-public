//
//  PrivateNoteRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/05/2023.
//

import SwiftUI

struct PrivateNoteRow: View {
    @ObservedObject var note: PrivateNote
    var nrPost: NRPost?
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment:.top) {
                Text(note.content_ == "" ? "(Empty note)" : note.content_)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sendNotification(.editingPrivateNote, note)
                    }
                Spacer()
                Ago(note.createdAt_)
                    .frame(alignment: .trailing)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 5)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
            if let nrPost {
                HStack {
                    PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25)
                        .onTapGesture {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
            }
            else if let contact = note.contact {
                HStack {
                    PFP(pubkey: contact.pubkey, contact: contact, size: 25)
                    Text(contact.anyName) // Name
                        .foregroundColor(.secondary)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if contact.nip05veried, let nip05 = contact.nip05 {
                        NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                            .layoutPriority(3)
                    }
                    Text(contact.about ?? "").lineLimit(1)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(ContactPath(key: contact.pubkey))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        
    }
}
