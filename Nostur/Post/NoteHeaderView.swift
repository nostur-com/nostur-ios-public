//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//
import SwiftUI
import Compactor

struct NoteHeaderView: View {
    let nav:NavigationModel = .shared
    let vPost:VPost
    var singleLine:Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
                    if let contact = vPost.event.contact {
                        NameAndNip(contact: contact)
                    }
                    else {
                        Text("Anon") // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .redacted(reason: .placeholder)
                    }
                    
                    if (singleLine) {
                        Group {
                            Text("@\(vPost.event.username)").layoutPriority(1)
                            Text(" · ") //
                            Ago(vPost.event.date).layoutPriority(1) //
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: vPost.event.pubkey))
                }
            }
            if (!singleLine) {
                Text("@\(vPost.event.username) · \(vPost.event.ago)")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    struct NameAndNip: View {
        @ObservedObject var contact:Contact // for rendering nip check (after just verified) etc
 
        var body: some View {
            Text(contact.authorName) // Name
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .lineLimit(1)
                .layoutPriority(2)

            if (contact.nip05veried) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.blue)
                    .layoutPriority(3)
            }
        }
    }
}

struct NoteHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        let event7 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        if (event7 != nil) {
            NoteHeaderView(vPost: event7!)
                .withPreviewEnvironment()
        }
    }
}
