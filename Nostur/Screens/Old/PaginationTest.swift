////
////  PaginationTest.swift
////  Nostur
////
////  Created by Fabian Lachman on 02/02/2023.
////
//
//import SwiftUI
//
//struct PaginationTest: View {
//    
//    @FetchRequest(
//        sortDescriptors: [],
//        predicate: NSPredicate(format: "kind == 1 and replyToId == nil"),
//        animation: .none)
//    var events: FetchedResults<Event>
//    
//    @State var firstPageEvents: Slice<FetchedResults<Event>>? = nil
//    @State var pages: [Slice<FetchedResults<Event>>] = []
//    
//    let pageSize = 30.0
//    
////    init() {
////        //var startIndex: Int
////        // var endIndex: Int
////        // subscript(Int) -> Result // Gets the entity at the specified index.
////        // .distance between indexes
////        // func index(Self.Index, offsetBy: Int, limitedBy: Self.Index) -> Self.Index?
////        //func index(after: Self.Index) -> Self.Index  //Returns the position immediately after the given index.
////        //func index(before: Self.Index) -> Self.Index
////
////        //subscript(Range<Self.Index>) -> Self.SubSequence
////// let firstWord = text.prefix(while: { $0 != " " })
////
////        //removeFirst(Int) Removes the specified number of elements from the beginning of the collection.
////
////
////        ///A collection and its slices share the same indices. An element of a collection is located under the same index in a slice as in the base collection, as long as neither the collection nor the slice has been mutated since the slice was created.
////
////
//////        events.drop
////
////
////
////    }
//    
//    var body: some View {
//        ScrollView {
//            if (firstPageEvents != nil) {
//                VStack {
//                    ForEach(firstPageEvents!) { event in
//                        NoteRowView(event: event)
//                    }
//                }
//            }
//            LazyVStack {
//                ForEach(pages, id:\.startIndex) { events in
//                    FPage(events: events)
//                }
//            }
//        }
//        .safeAreaInset(edge: .top) {
//            Text("Events: \(events.count). First page: \(firstPageEvents?.count ?? 0)")
//        }
//        .onAppear {
//            let pageCount = Int(floor(Double(events.count) / pageSize))
//            
//            // First page
//            let eventsOnFirstPage = events.count % Int(pageSize)
//            firstPageEvents = events[0..<eventsOnFirstPage]
//            
//            // All other pages
//            for loopCount in 0..<pageCount {
//                
//                let end = events.count - (loopCount * Int(pageSize)) // 153 - (0 * 30)
//                let start = end - Int(pageSize)         // end - 30 = 123
//                
//                let eventsRange = events[start..<end]
//                
//                pages.insert(eventsRange, at: 0)
//            }
//        }
//    }
//}
//
//
//
//struct FPage: View {
//    var events:Slice<FetchedResults<Event>>
////    var events:[Event]
//    
//    var body: some View {
//        VStack {
//            ForEach(events) { event in
//                NoteRowView(event: event)
//                    .id(event.id)
//            }
//        }
//    }
//}
//
//struct PaginationTest_Previews: PreviewProvider {
//    static var previews: some View {
//        PaginationTest()
//            .withPreviewEnvironment()
//    }
//}
