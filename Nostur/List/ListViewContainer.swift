//
//  ListViewContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//



import SwiftUI

struct ListViewContainer: View {
    
    let vm:LVM

    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            ListView(vm:vm)
            ListUnreadCounter(vmCounter: vm.lvmCounter)
            NewNoteButton(showingNewNote: $showingNewNote)
                .sheet(isPresented: $showingNewNote) {
                    NavigationStack {
                        NewNote(noteCancellationId: $noteCancellationId)
                    }
                }
        }
        .background(Color("ListBackground"))
        
//        .onChange(of: ns.followingPublicKeys) { pubkeys in
//            guard listType == .account else { return }
//            vm.changeFollowers(pubkeys:pubkeys)
//        }
//        .onChange(of: ns.explorePubkeys) { pubkeys in
//            guard listType == .explore else { return }
//            vm.changeFollowers(pubkeys:pubkeys)
//        }
    }
}

enum ListType {
    case account
    case explore
    case list
}
