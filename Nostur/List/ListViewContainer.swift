//
//  ListViewContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//

import SwiftUI

struct ListViewContainer: View, Equatable {
    static func == (lhs: ListViewContainer, rhs: ListViewContainer) -> Bool {
        lhs.pubkey == rhs.pubkey
        && lhs.pubkeys.count == rhs.pubkeys.count
        && lhs.listId == rhs.listId
    }
    
    @EnvironmentObject var ns:NosturState
    @StateObject var vm:LVM
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    let listId:String
    let listType:ListType
    @State var pubkey:String = ""
    @State var pubkeys:Set<String> = []
    
    init(pubkey:String, pubkeys:Set<String>, listId: String, listType: ListType) {
        self.listId = listId
        self.listType = listType
        let lvm = LVM(pubkey: pubkey, pubkeys: pubkeys, listId: listId)
        self._vm = StateObject(wrappedValue: lvm)
        self.showingNewNote = showingNewNote
        self.noteCancellationId = noteCancellationId
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            ListView(vm:vm, vmState:vm.lvmState)
            ListUnreadCounter(vmCounter: vm.lvmCounter)
            NewNoteButton(showingNewNote: $showingNewNote)
                .sheet(isPresented: $showingNewNote) {
                    NavigationStack {
                        NewNote(noteCancellationId: $noteCancellationId)
                    }
                }
        }
        .background(Color("ListBackground"))
        .onChange(of: listId) { newListId in
            pubkeys =  listType == .account ? ns.followingPublicKeys : ns.explorePubkeys
            
            vm.changeLVM(pubkey:pubkey,
                         pubkeys: newListId == "Following" ? ns.followingPublicKeys : ns.explorePubkeys,
                         listId: listId)
            
            //            vm.performFetch()
        }
        .onChange(of: ns.activeAccountPublicKey) { newPubkey in
            print("🟣🟣🟣🟣🟣🟣🟣🟣 ACCOUNT CHANGED 🟣🟣🟣🟣🟣🟣🟣")
            print("🟣🟣🟣🟣🟣🟣🟣🟣 following: \(ns.followingPublicKeys.count) 🟣🟣🟣🟣🟣🟣🟣")
            print("🟣🟣🟣🟣🟣🟣🟣🟣 explore: \(ns.explorePubkeys.count) 🟣🟣🟣🟣🟣🟣🟣")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pubkey = newPubkey
                pubkeys =  listType == .account ? ns.followingPublicKeys : ns.explorePubkeys
                
                vm.changeLVM(pubkey:newPubkey,
                             pubkeys: listType == .account ? ns.followingPublicKeys : ns.explorePubkeys,
                             listId: listId)
            }
        }
        .onChange(of: ns.followingPublicKeys) { pubkeys in
            guard listType == .account else { return }
            vm.changeFollowers(pubkeys:pubkeys)
        }
        .onChange(of: ns.explorePubkeys) { pubkeys in
            guard listType == .explore else { return }
            vm.changeFollowers(pubkeys:pubkeys)
        }
    }
}

enum ListType {
    case account
    case explore
    case list
}
