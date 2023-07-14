//
//  NEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2023.
//

import SwiftUI

struct NEventView: View {
    
    let identifier:ShareableIdentifier
        
    var body: some View {
        if let eventId = identifier.eventId {
            NEventViewInner(predicate: NSPredicate(format: "id == %@", eventId), identifier: identifier)
        }
    }
    
    struct NEventViewInner: View {
        
        @State var nrPost:NRPost?
        @State var fetchTask:Task<Void, Never>?
        
        private var fetchRequest: FetchRequest<Event>
        private var events: FetchedResults<Event> {
            fetchRequest.wrappedValue
        }
        private var identifier:ShareableIdentifier
        
        init(predicate: NSPredicate, identifier:ShareableIdentifier) {
            fetchRequest = FetchRequest(
                sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
                predicate: predicate
            )
            self.identifier = identifier
         }
        
        var body: some View {
            VStack {
                if let nrPost = nrPost, nrPost.blocked {
                    HStack {
                        Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                        Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                            .buttonStyle(.bordered)
                    }
                    .padding(.leading, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                else if let nrPost = nrPost {
                    if nrPost.kind == 30023 {
                        ArticleView(nrPost, hideFooter: true)
//                            .background(
//                                Color.systemBackground
//                                    .cornerRadius(15)
//                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(.regularMaterial, lineWidth: 1)
                            )
                    }
                    else {
                        QuotedNoteFragmentView(nrPost: nrPost)
                    }
                }
                else if let event = events.first {
                    CenteredProgressView()
                        .frame(height: 250)
                        .task {
                            DataProvider.shared().bg.perform {
                                let bgEvent = DataProvider.shared().bg.object(with: event.objectID) as! Event
                                let nrPost = NRPost(event: bgEvent)
                                DispatchQueue.main.async {
                                    self.nrPost = nrPost
                                }
                            }
                        }
                }
                else {
                    CenteredProgressView()
                        .frame(height: 250)
                        .onAppear {
                            guard let eventId = identifier.eventId else {
                                L.og.info("\(identifier.bech32string) has no eventId")
                                return
                            }
                            L.og.info("🟢 Fetching for NEventView \(eventId) / \(identifier.bech32string)")
                            req(RM.getEvent(id: eventId))
                            
                            if !identifier.relays.isEmpty {
                                fetchTask = Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    let ctx = DataProvider.shared().bg
                                    await ctx.perform {
                                        // If we don't have the event after X seconds, fetch from relay hint
                                        if (try? Event.fetchEvent(id: eventId, context: ctx)) == nil {
                                            if let relay = identifier.relays.first {
                                                EphemeralSocketPool.shared.sendMessage(RM.getEvent(id: eventId), relay: relay)
                                            }
                                            // TODO: hmm we need to get contact also...
                                        }
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            if let task = fetchTask {
                                task.cancel()
                            }
                        }
                }
            }
        }
    }
}

struct NEventView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let identifier = try? ShareableIdentifier("nevent1qqspg0h7quunckc8a7lxag0uvmpeewv9hx8cs3r9pmwsp77tqsfz3gcens7um") {
                    NEventView(identifier: identifier)
                }
            }
        }
    }
}
