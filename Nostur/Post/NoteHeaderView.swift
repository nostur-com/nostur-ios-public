//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.

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
                        DataProvider.shared().bg.perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteHeaderView.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
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
                    .onTapGesture {
                        navigateTo(ContactPath(key: nrPost.pubkey))
                    }
                
                if (singleLine) {
                    Group {
                        Text(verbatim:"@\(String(nrPost.pubkey.suffix(11)))").layoutPriority(1)
                        Text(verbatim:" · ") //
                        Ago(nrPost.createdAt, agoText: nrPost.ago)
                            .equatable()
                            .layoutPriority(2)
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
        }
        if (!singleLine) {
            HStack {
                Text(verbatim:"@\(String(nrPost.pubkey.suffix(11)))").layoutPriority(1)
                Text(verbatim:" · ") //
                Ago(nrPost.createdAt, agoText: nrPost.ago)
                    .equatable()
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
        HStack(alignment: .top, spacing: 5) {
            Group {
                Text(contact.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        navigateTo(ContactPath(key: nrPost.pubkey))
                    }
                
                if contact.couldBeImposter == 1 {
                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                        .padding(.horizontal, 8)
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .layoutPriority(2)
                }
                else if (contact.nip05verified) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color("AccentColor"))
                        .layoutPriority(3)
                }
                
                if (singleLine) {
                    Ago(nrPost.createdAt, agoText: nrPost.ago)
                        .equatable()
                        .layoutPriority(2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onAppear {
            if contact.metadata_created_at == 0 {
                EventRelationsQueue.shared.addAwaitingContact(contact.contact, debugInfo: "NoteHeaderView.001")
                QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
            }
        }
        .task {
            guard contact.metadata_created_at != 0 else { return }
            guard contact.couldBeImposter == -1 else { return }
            guard !contact.following else { return }
            
            DataProvider.shared().bg.perform {
                guard let account = NosturState.shared.bgAccount else { return }
                guard let similarContact = account.follows_.first(where: {
                    isSimilar(string1: $0.anyName.lowercased(), string2: contact.anyName.lowercased())
                }) else { return }
                guard let cPic = contact.pictureUrl, let wotPic = similarContact.picture else { return }
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    DispatchQueue.main.async {
                        contact.couldBeImposter = similarPFP ? 1 : 0
                        DataProvider.shared().bg.perform {
                            contact.contact.couldBeImposter = similarPFP ? 1 : 0
//                            DataProvider.shared().bgSave()
                        }
                    }
                }
            }
        }
        .onDisappear {
            if contact.metadata_created_at == 0 {
                QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
            }
        }
        if (!singleLine) {
            Ago(nrPost.createdAt, agoText: nrPost.ago)
                .equatable()
                .layoutPriority(2)
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
                            Text(verbatim:"@\(username)").layoutPriority(1)
                            Text(verbatim:" · ") //
                            Text(verbatim:"1s")
                                .layoutPriority(2)
                        }
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            if (!singleLine) {
                Text(verbatim: "@\(username) · 1s")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct NameAndNip: View {
    @ObservedObject var contact:NRContact // for rendering nip check (after just verified) etc
    
    var body: some View {
        Text(contact.anyName) // Name
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
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
                PreviewHeaderView(authorName: "Fabian", username: "fabian")
                
                if let p = PreviewFetcher.fetchNRPost("953dbf6a952f43f70dbb4d6432593ba5b7f149a786d1750e4aa4cef40522c0a0") {
                    NoteHeaderView(nrPost: p)
                }
            }
        }
    }
}
