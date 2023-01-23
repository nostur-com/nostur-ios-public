////
////  NoteThreadView.swift
////  Nostur
////
////  Created by Fabian Lachman on 23/01/2023.
////
//
//import SwiftUI
//
//struct NoteThreadView: View {
//    
//    var note:Event
//    var replies:FetchedResults<Event>
//    var reactions:FetchedResults<Event>
//    
//    var body: some View {
//        
//        // NEED?
//        // note 1
//        // note.contact
//        
//        // note.replies 1
//        // note.reactions 7
//        
//        NoteView(note: Note(event: note, responses: replies.reversed()))
//        
//        
//        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
//    }
//}
//
//// FOR PREVIEW
//struct NoteThreadWrapper: View {
//    
//    @Environment(\.managedObjectContext) var viewContext
//        
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)],
//        predicate: NSPredicate(format: "id == %@", "6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81"),
//        animation: .none)
//    var events: FetchedResults<Event>
//    
//
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)], predicate: NSPredicate(format: "replyToId == %@ AND kind == 0", "6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81"))
//    var replies:FetchedResults<Event>
//    
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)], predicate: NSPredicate(format: "replyToId == %@ AND kind == 7", "6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81"))
//    var reactions:FetchedResults<Event>
//    
//    var body: some View {
//        NoteThreadView(note:events.first!, replies:replies, reactions:reactions)
//    }
//}
//
//struct NoteThreadView_Previews: PreviewProvider {
//    static var previews: some View {
//        
//        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
//        let cm = ConnectionManager()
//        
//        NoteThreadWrapper()
//            .environment(\.managedObjectContext,
//                          EventsProvider.preview.container.viewContext)
//            .environmentObject(accountState)
//            .environmentObject(cm)
//    }
//}
