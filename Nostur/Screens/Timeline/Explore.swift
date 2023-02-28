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
    
    var body: some View {
        ZStack {
            ExploreContainer()
            NewNoteButton(showingNewNote: $showingNewNote)
            UnreadCounter()
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
    }
}

struct ExploreContainer: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @Environment(\.managedObjectContext) var viewContext
//    @State var showingNewNote = false

    
    var body: some View {
        let _ = Self._printChanges()
        if ns.account != nil && ns.globalPubkeys.count > 0 {
            Timeline(pubkey: ns.account!.publicKey, pubkeys: ns.globalPubkeys, context: viewContext, id: "EXPLORE")
        }
        else {
            ProgressView()
                .onAppear() {
                    if (ns.accounts.count == 0) {
//                        ns.isOnboarding = true
                    }
                    else if (ns.globalPubkeys.count == 0) {
                        // TODO:
                        // fetch guest account kind 3
                        // add to ns.globalPubkeys
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
