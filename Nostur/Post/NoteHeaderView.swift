//
//  NoteHeaderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2023.

import SwiftUI

struct NoteHeaderView: View {
    
    let nrPost:NRPost
    @ObservedObject var pfpAttributes: NRPost.PFPAttributes
    var singleLine:Bool = true
    
    init(nrPost: NRPost, singleLine: Bool = true) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.singleLine = singleLine
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing:0) { // Name + menu "replying to"
            if let contact = pfpAttributes.contact {
                PostHeader(contact: contact, nrPost:nrPost, singleLine:singleLine)
//                    .background(Color.random)
            }
            else {
                PlaceholderPostHeader(nrPost: nrPost, singleLine: singleLine)
                    .onAppear {
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteHeaderView.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
            }
        }
//        .transaction { t in
//            t.animation = nil
//        }
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
//                    .transaction { t in
//                        t.animation = nil
//                    }
                    .onTapGesture {
                        if let nrContact = nrPost.contact {
                            navigateTo(nrContact)
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
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
    @ObservedObject public var contact:NRContact
    public let nrPost:NRPost
    public let singleLine:Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Group {
                Text(contact.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
//                    .transaction { t in
//                        t.animation = nil
//                    }
                    .onTapGesture {
                        navigateTo(contact)
                    }
                
                if contact.couldBeImposter == 1 {
                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                        .padding(.horizontal, 8)
                        .background(.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top, 3)
                        .layoutPriority(2)
                }
//                else if (contact.nip05verified) {
//                    Image(systemName: "checkmark.seal.fill")
//                        .foregroundColor(Color("AccentColor"))
//                        .layoutPriority(3)
//                }
                
                if (singleLine) {
                    Ago(nrPost.createdAt, agoText: nrPost.ago)
                        .equatable()
                        .layoutPriority(2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
//        .transaction { t in
//            t.animation = nil
//        }
        .onAppear {
            if contact.metadata_created_at == 0 {
                EventRelationsQueue.shared.addAwaitingContact(contact.contact, debugInfo: "NoteHeaderView.001")
                QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
            }
        }
        .task {
            guard !SettingsStore.shared.lowDataMode else { return }
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            guard contact.metadata_created_at != 0 else { return }
            guard contact.couldBeImposter == -1 else { return }
            guard !contact.following else { return }
            guard !NewOnboardingTracker.shared.isOnboarding else { return }
            
            let contactAnyName = contact.anyName.lowercased()
            let currentAccountPubkey = NRState.shared.activeAccountPublicKey
            let cPubkey = contact.pubkey
            
            bg().perform {
                guard let account = account() else { return }
                guard account.publicKey == currentAccountPubkey else { return }
                guard let similarContact = account.follows.first(where: {
                    $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName)
                }) else { return }
                guard let cPic = contact.pictureUrl, similarContact.picture != nil, let wotPic = similarContact.pictureUrl else { return }
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    DispatchQueue.main.async {
                        guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                        contact.couldBeImposter = similarPFP ? 1 : 0
                        bg().perform {
                            guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
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
                    
                    if (singleLine) {
                        Group {
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
                Text(verbatim: "1s")
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct NameAndNip: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject var contact:NRContact // for rendering nip check (after just verified) etc
    
    var body: some View {
        Text(contact.anyName) // Name
            .foregroundColor(.primary)
            .fontWeight(.bold)
            .lineLimit(1)
            .layoutPriority(2)
            .onAppear {
                if contact.metadata_created_at == 0 {
                    EventRelationsQueue.shared.addAwaitingContact(contact.contact, debugInfo: "NameAndNip.001")
                    QueuedFetcher.shared.enqueue(pTag: contact.pubkey)
                }
            }
            .onDisappear {
                if contact.metadata_created_at == 0 {
                    QueuedFetcher.shared.dequeue(pTag: contact.pubkey)
                }
            }
        
        if contact.couldBeImposter == 1 {
            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                .padding(.horizontal, 8)
                .background(.red)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 3)
                .layoutPriority(2)
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
                PreviewHeaderView(authorName: "Fabian")
                
                if let p = PreviewFetcher.fetchNRPost("953dbf6a952f43f70dbb4d6432593ba5b7f149a786d1750e4aa4cef40522c0a0") {
                    NoteHeaderView(nrPost: p)
                }
            }
        }
    }
}
