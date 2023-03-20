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
    
    var onDismiss:() -> Void
    
    init(privateNote: PrivateNote, onDismiss: @escaping () -> Void) {
        self.privateNote = privateNote
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField(
                    text: $privateNote.content_,
                    prompt: Text("Enter private note for yourself"),
                    axis: .vertical) {
                    Text("Private note")
                }.lineLimit(10, reservesSpace: true)
            }
            .navigationTitle("Edit private note")
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
                        }
                        catch { print("problem saving private note \(error)") }
                        dismiss()
                    }
                }
            }
            .actionSheet(item: $privateNoteToRemove) { pNote in
                ActionSheet(
                    title: Text("Delete private note"),
//                    message: account.privateKey != nil
//                    ? Text("""
//                             Make sure you have a back-up of your private key (nsec)
//                             Nostur cannot recover your account without it
//                             """)
//                    : Text("""
//                             Account: @\(account.name) / \(account.display_name)
//                             """)
//                    ,
                    buttons: [
                        .destructive(Text("Delete"), action: {
                            do {
                                ns.objectWillChange.send()
                                privateNote.post?.objectWillChange.send()
                                privateNote.contact?.objectWillChange.send()
                                viewContext.delete(privateNote)
                                try viewContext.save()
                                dismiss()
                            }
                            catch { print("problem deleting private note \(error)") }
                        }),
                        .cancel(Text("Cancel"))
                    ])
            }
        }
    }
}

struct EditPrivateNoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        
        let note:PrivateNote = {
            let note = PrivateNote(context: EventsProvider.preview.container.viewContext)
            note.createdAt = Date.now
            note.updatedAt = Date.now
            note.content = ""
            note.by = PreviewFetcher.fetchAccount()
            note.post = PreviewFetcher.fetchEvent()
            return note
        }()
        
        
        EditPrivateNoteSheet(privateNote: note, onDismiss: {})
            .withPreviewEnvironment()
    }
}
