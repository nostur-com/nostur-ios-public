//
//  Reactions.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/02/2023.
//

import SwiftUI

struct NoteReactions: View {
    
    @EnvironmentObject var sp:SocketPool
    
    let id:String
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    var reactions:FetchedResults<Event>
    var reactions_:[Event] { Array(reactions) }
    
    init(id:String) {
        self.id = id
        _reactions = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "kind == 7 AND reactionToId == %@", id))
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            ForEach(reactions) { reaction in
                ReactionRow(reaction: reaction)
            }
            Spacer()
        }
        .onAppear {
            var missing:[String] = []
            for reaction in reactions_ {
                if reaction.contact == nil || reaction.contact?.updated_at == 0 {
                    missing.append(reaction.pubkey)
                }
            }
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missing)))
        }
        .onChange(of: reactions_) { newValue in
            var missing:[String] = []
            for reaction in newValue {
                if reaction.contact == nil || reaction.contact?.updated_at == 0 {
                    missing.append(reaction.pubkey)
                }
            }
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missing)))
        }
    }
}

struct ReactionRow: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    @ObservedObject var reaction:Event
    
    var body: some View {
        HStack(alignment: .top) {
            ProfilePicView(pubkey: reaction.pubkey, contact: reaction.contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing:3) {
                            Text(reaction.contact?.authorName ?? "").font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if (reaction.contact?.nip05veried ?? false) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                            }
                        
                            Group {
                                Text("@\(reaction.contact?.username ?? reaction.authorKey )").layoutPriority(1)
                                Text(" · ") //
                                Text(reaction.ago).layoutPriority(1) //
                            }
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()
                    
                }
                Text(reaction.content == "+" ? "❤️" : reaction.content ?? "")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            nav.navigateTo(ContactPath(key: reaction.pubkey))
        }
        Divider()
    }
}

struct Reactions_Previews: PreviewProvider {
    static var previews: some View {
        
        let noteWithReactions = PreviewFetcher.fetchEvent("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81")
        
        VStack {
            if (noteWithReactions != nil) {
                NoteReactions(id: noteWithReactions!.id)
            }
        }
        .withPreviewEnvironment()
        
    }
}
