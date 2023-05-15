//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.
//
import SwiftUI

struct NoteHeaderView: View {
     
    @ObservedObject var nrPost:NRPost
    var singleLine:Bool = true
    
    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.singleLine = singleLine
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            if let contact = nrPost.contact {
                PostHeader(contact: contact, nrPost:nrPost, singleLine:singleLine)
            }
            else {
                PlaceholderPostHeader(nrPost: nrPost, singleLine: singleLine)
                    .onAppear {
                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
                        QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
            }
        }
    }
}

struct PlaceholderPostHeader: View {
    let nrPost:NRPost
    let singleLine:Bool
    
    var body: some View {
        HStack(spacing:2) {
            Group {
                Text(String(nrPost.pubkey.suffix(11))) // Name
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                
                if (singleLine) {
                    Group {
                        Text("@\(String(nrPost.pubkey.suffix(11)))").layoutPriority(1)
                        Text(" · ") //
                        Ago(nrPost.createdAt)
                            .layoutPriority(2)
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
        }
        if (!singleLine) {
            HStack {
                Text("@\(String(nrPost.pubkey.suffix(11)))").layoutPriority(1)
                Text(" · ") //
                Ago(nrPost.createdAt)
                    .layoutPriority(2)
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }
}

struct PostHeader: View {
    @ObservedObject var contact:NRContact
    let nrPost:NRPost
    let singleLine:Bool
    
    var body: some View {
        HStack(spacing:2) {
            Group {
                Text(contact.displayName ?? "") // Name
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                
                if (contact.nip05verified) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color("AccentColor"))
                        .layoutPriority(3)
                }
                
                if (singleLine) {
                    Group {
                        Text("@\(contact.username ?? String(contact.pubkey.suffix(11)))").layoutPriority(1)
                        Text(" · ") //
                        Ago(nrPost.createdAt)
                            .layoutPriority(2)
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .onAppear {
            if contact.metadata_created_at == 0 {
                EventRelationsQueue.shared.addAwaitingContact(contact.contact)
                QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
            }
        }
        .onDisappear {
            if contact.metadata_created_at == 0 {
                QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
            }
        }
        if (!singleLine) {
            HStack(spacing:2) {
                Text("@\(contact.anyUsername)").layoutPriority(1)
                Text(" · ") //
                Ago(nrPost.createdAt)
                    .layoutPriority(2)
            }
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }
}

struct PreviewHeaderView: View {

    var authorName:String
    var username:String
    var nip05verified = false
    var singleLine:Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
    
                    Text(authorName) // Name
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .layoutPriority(2)

                    if (nip05verified) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color("AccentColor"))
                            .layoutPriority(3)
                    }
                    
                    
                    
                    if (singleLine) {
                        Group {
                            Text("@\(username)").layoutPriority(1)
                            Text(" · ") //
                            Text("1s")
                                .layoutPriority(2)
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            if (!singleLine) {
                Text("@\(username) · 1s")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct NameAndNip: View {
//    @ObservedObject var contact:Contact // for rendering nip check (after just verified) etc
//    var contact:NRContact
    @ObservedObject var contact:NRContact // for rendering nip check (after just verified) etc

    var body: some View {
        Text(contact.displayName ?? "") // Name
            .foregroundColor(.primary)
            .fontWeight(.bold)
            .lineLimit(1)
            .layoutPriority(2)

        if (contact.nip05verified) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Color("AccentColor"))
                .layoutPriority(3)
        }
    }
}

struct NoteHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack {
            PreviewHeaderView(authorName: "Fabian", username: "fabian")
            
            let event7 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            if (event7 != nil) {
                NoteHeaderView(nrPost: event7!)
                    .withPreviewEnvironment()
            }
        }
        
    }
}
