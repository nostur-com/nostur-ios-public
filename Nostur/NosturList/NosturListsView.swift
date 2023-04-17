//
//  NosturLists.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//

import SwiftUI

struct NosturListsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest
    var lists:FetchedResults<NosturList>
    
    @State var confirmDeleteShown = false
    @State var listToDelete:NosturList? = nil
    @State var newList:NosturList? = nil
    
    init() {
        let r = NosturList.fetchRequest()
        r.predicate = NSPredicate(value: true)
        r.sortDescriptors = [NSSortDescriptor(keyPath:\NosturList.createdAt, ascending: false)]
        _lists = FetchRequest(fetchRequest: r)
    }
        
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
                    newList = NosturList(context: DataProvider.shared().viewContext)
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
        .sheet(item: $newList) { newList in
            NavigationStack {
                NewListSheet(list: newList)
            }
        }
    }
}

struct ListRow: View {
    @ObservedObject var list:NosturList
    
    var body: some View {
        Text("List: \(list.name ?? "")")
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
