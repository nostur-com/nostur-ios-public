//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI

struct TestTestView: View {
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
//        predicate: NSPredicate(format: "kind == 1 and replyToId == nil"),
        animation: .none)
    var events: FetchedResults<Event>
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(events) { event in
                    Text("text")
                }
//                ForEach(events) { event in
//                    NoteRowView(event:event)
//                }
//                ForEach(events.indices, id:\.self) { index in
//                    NoteRowView(event:events[index])
//                }
            }
        }
    }
}

struct TestTest_Previews: PreviewProvider {
    static var previews: some View {
        TestTestView()
            .withPreviewEnvironment()
    }
}
