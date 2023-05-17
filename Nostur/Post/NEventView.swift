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
                if let nrPost = nrPost {
                    QuotedNoteFragmentView(nrPost: nrPost)
                }
                else if let event = events.first {
                    CenteredProgressView()
                        .frame(height: 250)
                        .task {
                            DataProvider.shared().bg.perform {
//                                let transformer = VPostTransformer.bg
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
                                print("\(identifier.bech32string) has no eventId")
                                return
                            }
                            print("🟢 Fetching for NEventView \(eventId) / \(identifier.bech32string)")
                            req(RM.getEvent(id: eventId))
                            
                            if identifier.relays.count > 0 {
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
        NavigationStack {
            if let identifier = try? ShareableIdentifier("nevent1qqspg0h7quunckc8a7lxag0uvmpeewv9hx8cs3r9pmwsp77tqsfz3gcens7um") {
                NEventView(identifier: identifier)
            }
        }
        .withPreviewEnvironment()
        
    }
}
