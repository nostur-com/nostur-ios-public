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
    
    var ds:TimelineModel
    
    init() {
        self.ds = TimelineModel()
        self.ds.setId(id: "Following")
    }
    
    var body: some View {
        ZStack {
            FollowingContainer(ds:ds)
            NewNoteButton(showingNewNote: $showingNewNote)
            UnreadCounter(ds:ds)
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
    }
}

struct FollowingContainer: View {
    @EnvironmentObject var ns:NosturState
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @Environment(\.managedObjectContext) var viewContext
    var ds:TimelineModel

    
    var body: some View {
        let _ = Self._printChanges()
        if ns.account != nil && (ns.account!.follows?.count ?? 0) > 0 {
            Timeline(pubkey: ns.account!.publicKey, pubkeys: ns.followingPublicKeys, context: viewContext, id:"Following", ds:ds)
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
                    selectedSubTab = "Explore"
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




