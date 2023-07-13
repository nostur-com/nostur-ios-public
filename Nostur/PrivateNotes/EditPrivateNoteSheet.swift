//
//  EditPrivateNoteSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

struct EditPrivateNoteSheet: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var ns:NosturState
    
    @ObservedObject var privateNote:PrivateNote
    
    @State var privateNoteToRemove:PrivateNote?
    
    init(privateNote: PrivateNote) {
        self.privateNote = privateNote
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    text: $privateNote.content_,
                    prompt: Text("Enter private note for yourself", comment: "Placeholder in text field"),
                    axis: .vertical) {
                        Text("Private note", comment: "Label for private note edit field")
                }.lineLimit(10, reservesSpace: true)
            }
            .navigationTitle(String(localized: "Edit private note", comment: "Navigation title for private note edit screen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        privateNoteToRemove = privateNote
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        do {
                            ns.objectWillChange.send()
                            privateNote.post?.objectWillChange.send()
                            privateNote.contact?.objectWillChange.send()
                            try viewContext.save()
                            if let post = privateNote.post {
                                sendNotification(.postAction, PostActionNotification(type: .privateNote, eventId: post.id, hasPrivateNote: true))
                            }
                        }
                        catch { L.og.error("problem saving private note \(error)") }
                        dismiss()
                    }
                }
            }
            .actionSheet(item: $privateNoteToRemove) { pNote in
                ActionSheet(
                    title: Text("Delete private note", comment: "Sheet title"),
                    buttons: [
                        .destructive(Text("Delete", comment: "Button to delete"), action: {
                            ns.objectWillChange.send()
                            privateNote.post?.objectWillChange.send()
                            privateNote.contact?.objectWillChange.send()
                            dismiss()
                            
                            if let post = privateNote.post {
                                sendNotification(.postAction, PostActionNotification(type: .privateNote, eventId: post.id, hasPrivateNote: false))
                            }
                            
                            viewContext.delete(privateNote)
                            DataProvider.shared().save()
                        }),
                        .cancel(Text("Cancel"))
                    ])
            }
        }
    }
}

struct EditPrivateNoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer {
            VStack {
                let note:PrivateNote = {
                    let note = PrivateNote(context: DataProvider.shared().container.viewContext)
                    note.createdAt = Date.now
                    note.updatedAt = Date.now
                    note.content = ""
                    note.by = PreviewFetcher.fetchAccount()
                    note.post = PreviewFetcher.fetchEvent()
                    return note
                }()
                
                
                EditPrivateNoteSheet(privateNote: note)//, onDismiss: {})
            }
        }
    }
}
