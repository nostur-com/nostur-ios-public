//
//  ListManagerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI

struct ListManagerView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NosturList.createdAt, ascending: false)],
        predicate: NSPredicate(value: true))
    var lists:FetchedResults<NosturList>
    
    @State var confirmDeleteShown = false
    @State var listToDelete:NosturList? = nil
    
    var body: some View {
        List(lists) { list in
            NavigationLink(value: list) {
                ListRow(list: list)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            listToDelete = list
                            confirmDeleteShown = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
//                Button
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
    }
}


struct ListRow: View {
    @ObservedObject var list:NosturList
    
    var body: some View {
        Text("List: \(list.name ?? "")")
    }
}

struct ListManagerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ListManagerView()
                .withNavigationDestinations()
        }
        .withPreviewEnvironment()
    }
}
