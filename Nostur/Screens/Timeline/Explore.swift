//
//  Global.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//
import SwiftUI
import CoreData
import Combine
//import IsScrolling

struct ExploreStateIsolation: View {
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    var ds:TimelineModel
    
    init() {
        self.ds = TimelineModel()
        self.ds.setId(id: "Explore")
    }
    
    var body: some View {
        ZStack {
            ExploreContainer(ds:ds)
            NewNoteButton(showingNewNote: $showingNewNote)
            UnreadCounter(ds:ds)
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
    }
}

struct ExploreContainer: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var ds:TimelineModel

    var body: some View {
        let _ = Self._printChanges()
        if ns.account != nil && ns.explorePubkeys.count > 0 {
            Timeline(pubkey: ns.account!.publicKey, pubkeys: ns.explorePubkeys, context: viewContext, id: "Explore", ds:ds)
        }
        else {
            ProgressView()
                .onAppear() {
                    if (ns.accounts.count == 0) {
//                        ns.isOnboarding = true
                    }
                    else if (ns.explorePubkeys.count == 0) {
                        // TODO:
                        // fetch guest account kind 3
                        // add to ns.globalPubkeys
                        // Fetch updated contactlist for epxlorer feed
//                        let message = ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: NosturState.EXPLORER_PUBKEY))
//                        SocketPool.shared.sendMessage(message)
                    }
                }
        }
    }
}

struct Explore_Previews: PreviewProvider {
    
    static var previews: some View {
        ExploreStateIsolation()
            .withPreviewEnvironment()
    }
}
