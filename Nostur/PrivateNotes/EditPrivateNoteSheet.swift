//
//  EditPrivateNoteSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import NavigationBackport

struct EditPrivateNoteSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    private var privateNote: CloudPrivateNote
    
    @State private var privateNoteToRemove: CloudPrivateNote?
    @State private var noteText = ""
    
    init(privateNote: CloudPrivateNote) {
        self.privateNote = privateNote
    }
    
    var body: some View {
        Form {
            Group {
                if #available(iOS 16.0, *) {
                    TextField(
                        text: $noteText,
                        prompt: Text("Enter private note for yourself", comment: "Placeholder in text field"),
                        axis: .vertical) {
                            Text("Private note", comment: "Label for private note edit field")
                    }
                    .lineLimit(10, reservesSpace: true)
                }
                else {
                    TextField(
                        text: $noteText,
                        prompt: Text("Enter private note for yourself", comment: "Placeholder in text field")) {
                            Text("Private note", comment: "Label for private note edit field")
                    }
                    .lineLimit(10)
                }
            }
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundHidden()
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
                        privateNote.content = noteText
                        try viewContext.save()
                        L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
                        if let type = privateNote.type, type == CloudPrivateNote.PrivateNoteType.post.rawValue, let eventId = privateNote.eventId {
                            sendNotification(.postAction, PostActionNotification(type: .privateNote, eventId: eventId, hasPrivateNote: true))
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
                        dismiss()
                        
                        if let type = privateNote.type, type == CloudPrivateNote.PrivateNoteType.post.rawValue, let eventId = privateNote.eventId {
                            sendNotification(.postAction, PostActionNotification(type: .privateNote, eventId: eventId, hasPrivateNote: false))
                        }
                        
                        viewContext.delete(privateNote)
                        DataProvider.shared().saveToDiskNow(.viewContext)
                    }),
                    .cancel(Text("Cancel"))
                ])
        }
        .onAppear {
            noteText = privateNote.content_
        }
    }
}

struct EditPrivateNoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer {
            VStack {
                let note:CloudPrivateNote = {
                    let note = CloudPrivateNote(context: DataProvider.shared().container.viewContext)
                    note.createdAt = Date.now
                    note.updatedAt = Date.now
                    note.content = ""
                    note.eventId = PreviewFetcher.fetchEvent()?.id
                    note.type = CloudPrivateNote.PrivateNoteType.post.rawValue
                    return note
                }()
                
                
                EditPrivateNoteSheet(privateNote: note)//, onDismiss: {})
            }
        }
    }
}
