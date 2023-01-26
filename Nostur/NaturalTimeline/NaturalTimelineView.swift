//
//  NaturalTimelineView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI
import CoreData

struct NaturalTimelineView: View {
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    init(withReplies:Bool = false) {
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (withReplies) {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1 && replyToId == nil")
        }
        request.fetchLimit = 200
//        request.fetchBatchSize = 1
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        _events = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        VStack {
//            TimelineRefresher()
            ScrollView {
                LazyVStack {
                    ForEach(events, id:\.self) { event in
                        NoteRow(event: event)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = event.noteId
                                } label: {
                                    Label("Copy note id \(event.noteId)", systemImage: "doc.on.clipboard")
                                }
                                Button {
                                    UIPasteboard.general.string = event.id!
                                } label: {
                                    Label("Copy note id hex \(event.id!))", systemImage: "doc.on.clipboard")
                                }
                                Button {
                                    print("Unfollow @\(event.username)")
                                } label: {
                                    Label("Unfollow @\(event.username)", systemImage: "person.fill.xmark")
                                }
                                Button {
                                    print("Block @\(event.username)")
                                } label: {
                                    Label("Block @\(event.username)", systemImage: "slash.circle")
                                }
                            }
                                
                    }
                }
            }
        }
    }
}

struct NaturalTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        NaturalTimelineView()
            .withPreviewEnvironment()
    }
}
