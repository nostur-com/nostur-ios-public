//
//  NosturLists.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI

struct NosturListsView: View {
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\NosturList.createdAt, ascending: false)])
    var lists:FetchedResults<NosturList>
    
    @State var confirmDeleteShown = false
    @State var listToDelete:NosturList? = nil
    @State var newListSheet = false
        
    var body: some View {
        List(lists) { list in
            NavigationLink(value: list) {
                ListRow(list: list)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            listToDelete = list
                            confirmDeleteShown = true
                        } label: {
                            Label("DeleteDelete", systemImage: "trash")
                        }
                        
                    }
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Create new list") {
                    newListSheet = true
                }
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete list \(listToDelete?.name ?? "")", isPresented: $confirmDeleteShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let listToDelete = listToDelete else { return }
                viewContext.delete(listToDelete)
                DataProvider.shared().save()
                self.listToDelete = nil
            }
        }
        .sheet(isPresented: $newListSheet) {
            NavigationStack {
                NewListSheet()
            }
        }
    }
}

struct ListRow: View {
    @ObservedObject var list:NosturList
    let showPin:Bool
    
    init(list: NosturList, showPin:Bool = true) {
        self.list = list
        self.showPin = showPin
    }
    
    var body: some View {
        HStack {
            if showPin {
                Image(systemName: list.showAsTab ? "pin.fill" : "pin")
            }
            Text(list.name_)
            Spacer()
        }
    }
}

struct NosturListsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NosturListsView()
                .withNavigationDestinations()
        }
        .withPreviewEnvironment()
    }
}
