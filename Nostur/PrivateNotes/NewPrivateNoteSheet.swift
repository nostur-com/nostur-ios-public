//
//  NewPrivateNoteSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

struct NewPrivateNoteSheet: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @Environment(\.dismiss) var dismiss
    
    var post:Event?
    var contact:Contact?
    var onDismiss:() -> Void
    
    @State var content = ""
    
    init(contact:Contact? = nil, post: Event? = nil, onDismiss: @escaping () -> Void) {
        self.post = post
        self.contact = contact
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    text: $content,
                    prompt: Text("Enter private note about \(contact != nil ? (contact?.name ?? "this user") : "this post") for yourself"),
                    axis: .vertical) {
                    Text("Private note")
                }.lineLimit(10, reservesSpace: true)
            }
            .navigationTitle("New private note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        do {
                            guard post != nil || contact != nil else { return }
                            ns.objectWillChange.send()
                            post?.objectWillChange.send()
                            contact?.objectWillChange.send()
                            if let newPrivateNote = post != nil
                                ? PrivateNote.createNewFor(ns.account!, andPost: post!, context: viewContext)
                                : PrivateNote.createNewFor(ns.account!, andContact: contact!, context: viewContext) {
                             
                                newPrivateNote.content = content
                            }
//                            privateNote.post?.objectWillChange.send()
                            try viewContext.save()
                        }
                        catch { print("problem saving private note \(error)") }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NewPrivateNoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack {
            if let event = PreviewFetcher.fetchEvent() {
                NewPrivateNoteSheet(post: event, onDismiss: {})
            }
        }
        .withPreviewEnvironment()
    }
}
