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
        ListView(vm:vm)
            .overlay(alignment: .topTrailing) {
                ListUnreadCounter(vmCounter: vm.lvmCounter)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
            }
            .overlay(alignment: .bottomTrailing) {
                NewNoteButton(showingNewNote: $showingNewNote)
                    .padding([.top, .leading, .bottom], 10)
                    .padding([.trailing], 25)
            }
            .overlay(alignment: .bottom) {
                ProcessingStatus()
                    .opacity(0.85)
                    .padding(.bottom, 10)
            }
        .background(Color("ListBackground"))
        .sheet(isPresented: $showingNewNote) {
            NavigationStack {
                NewNote(noteCancellationId: $noteCancellationId)
            }
        }
    }
}

enum ListType {
    case account
    case explore
    case list
}
