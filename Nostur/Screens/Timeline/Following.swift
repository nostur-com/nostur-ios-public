//
//  TL3.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/02/2023.
//
import SwiftUI
import CoreData
import Combine
//import IsScrolling

struct FollowingStateIsolation: View {
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        ZStack {
            FollowingContainer()
            NewNoteButton(showingNewNote: $showingNewNote)
            UnreadCounter()
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
    }
}

struct FollowingContainer: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @Environment(\.managedObjectContext) var viewContext
//    @State var showingNewNote = false

    
    var body: some View {
        let _ = Self._printChanges()
        if ns.account != nil && (ns.account!.follows?.count ?? 0) > 0 {
            Timeline(pubkey: ns.account!.publicKey, pubkeys: ns.followingPublicKeys, context: viewContext, id:"FOLLOWING")
        }
        else if ns.account == nil {
            Text("No account")
                .onAppear() {
                    if (ns.accounts.count == 0) {
//                        ns.isOnboarding = true
                    }
                }
        }
        else {
            VStack {
                Text("You are not following anyone yet, visit the explore tab and follow some people")
                    .multilineTextAlignment(.center)
                    .padding(/*@START_MENU_TOKEN@*/.all, 30.0/*@END_MENU_TOKEN@*/)
                    
                Button {
                    nav.selectedSubTab = "Explore"
                } label: {
                    Text("Explore")
                }.buttonStyle(.borderedProminent)
            }
            // TODO: Add some follow suggestions here.
        }
    }
}

struct Following_Previews: PreviewProvider {
        
    static var previews: some View {
        FollowingStateIsolation()
            .withPreviewEnvironment()
    }
}




