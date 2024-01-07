//
//  NewPrivateNoteSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import NavigationBackport

struct NewPrivateNoteSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    private var post:Event?
    private var contact:Contact?
    
    @State private var content = ""
    
    init(contact:Contact? = nil, post: Event? = nil) {
        self.post = post
        self.contact = contact
    }
    
    var body: some View {
        NBNavigationStack {
            Form {
                if #available(iOS 16.0, *) {
                    TextField(
                        text: $content,
                        prompt: {
                            if contact != nil {
                                if let name = contact?.anyName {
                                    return Text("Enter private note about \(name) for yourself", comment: "Placeholder for entering note about (name)")
                                }
                                else {
                                    return Text("Enter private note about this user for yourself", comment: "Placeholder for entering private note")
                                }
                            }
                            else {
                                return Text("Enter private note about this post for yourself", comment:"Placeholder for entering private note")
                            }
                        }(),
                        axis: .vertical) {
                            Text("Private note")
                        }
                        .lineLimit(10, reservesSpace: true)
                }
                else {
                    TextField(
                        text: $content,
                        prompt: {
                            if contact != nil {
                                if let name = contact?.anyName {
                                    return Text("Enter private note about \(name) for yourself", comment: "Placeholder for entering note about (name)")
                                }
                                else {
                                    return Text("Enter private note about this user for yourself", comment: "Placeholder for entering private note")
                                }
                            }
                            else {
                                return Text("Enter private note about this post for yourself", comment:"Placeholder for entering private note")
                            }
                        }()) {
                            Text("Private note")
                        }
                        .lineLimit(10)
                }
            }
            .navigationTitle(String(localized: "New private note", comment: "Navigation title for new private note screen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        dismiss()
                        do {
                            guard post != nil || contact != nil else { return }
                            post?.objectWillChange.send()
                            contact?.objectWillChange.send()
                            if let post {
                                if let newPrivateNote = CloudPrivateNote.createNewFor(post, context: viewContext) {
                                    newPrivateNote.content = content
                                    
                                    sendNotification(.postAction, PostActionNotification(type: .privateNote, eventId: post.id, hasPrivateNote: true))
                                }
                            }
                            else if let contact {
                                if let newPrivateNote = CloudPrivateNote.createNewFor(contact, context: viewContext) {
                                    newPrivateNote.content = content
                                }
                            }
                            
                            try viewContext.save()
                        }
                        catch { L.og.error("problem saving private note \(error)") }
                    }
                }
            }
        }
    }
}

struct NewPrivateNoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            VStack {
                if let event = PreviewFetcher.fetchEvent() {
                    NewPrivateNoteSheet(post: event)//, onDismiss: {})
                }
            }
        }
    }
}
