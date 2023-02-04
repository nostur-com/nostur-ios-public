//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        if (ns.account == nil) {
            Text("Please choose account first")
        }
        else {
            List {
                ForEach(Array(ns.account!.blockedContacts ?? []), id:\.objectID) { contact in
                    ProfileRow(withoutFollowButton: true, contact: contact)
                }
                .onDelete { offsets in
                    withAnimation {
                        offsets.map { Array(ns.account!.blockedContacts ?? [] )[$0] }.forEach(viewContext.delete)
                        do { try viewContext.save() } catch {
                            let nsError = error as NSError
                            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                        }
                    }
                }
            }
        }
    }
}

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        BlockListView()
            .withPreviewEnvironment()
    }
}
