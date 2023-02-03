//
//  PaginationTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

// DEZE IS GOED.. MAAR 3 x REVERSE..!!

import SwiftUI
import CoreData

struct PaginationTest2: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest
    var events: FetchedResults<Event>

//    @State var pages: [Slice<FetchedResults<Event>>] = []
    @State var pages: [ArraySlice<Event>] = []
    
    let pageSize = 3
    
    init() {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
//        fr.fetchBatchSize = 20
        fr.fetchLimit = 10
//        fr.fetchOffset = 2
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(pages.reversed(), id:\.startIndex) { events in
                    APage(events: events.reversed())
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack {
                Text("Events: \(events.count)")
                Text("Pages: \(Int(ceil(Double(events.count) / Double(pageSize))))")
                HStack {
                    Button {
                        let newEvent = Event(context: viewContext)
                        newEvent.id = UUID().description
                        newEvent.kind = 1
                        newEvent.created_at = Int64(Date.now.timeIntervalSince1970)
                        
                    } label: { Text("Add event") }
                    Button { updatePages() } label: { Text("Pages") }
                }
            }.buttonStyle(.borderedProminent)
            
            
        }
        .onChange(of: events.first) { newestEvent in
            updatePages()
        }
        .onAppear {
            setupPages()
        }
    }
    
    func setupPages() {
        let rev = Array(events.reversed())
        let pageCount = Int(ceil(Double(rev.count) / Double(pageSize))) // 33 / 3 = 11
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<11
            
            let start = (loopCount * pageSize) // 0 * 3 = 0, 1 * 3 = 3, 2 * 3 = 6
            let end = start + pageSize // 0 + 3 = 3, 3 + 3 = 6, 6 + 3 = 9
    
            // events.count = 5
            // [start..<5]
            
            let notOutOfBoundsEnd = end > rev.count ? rev.count : end
            let eventsRange = rev[start..<notOutOfBoundsEnd]
            
            pages.append(eventsRange)
        }
    }
    func updatePages() {
        let rev = Array(events.reversed())
        pages = []
        let pageCount = Int(ceil(Double(rev.count) / Double(pageSize))) // 5
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<5
            
            let start = (loopCount * pageSize)
            let end = start + pageSize
            
            let notOutOfBoundsEnd = end > rev.count ? rev.count : end
            let eventsRange = rev[start..<notOutOfBoundsEnd]
            
            pages.append(eventsRange)
        }
    }
}

struct APage: View {
    
    var events:ReversedCollection<ArraySlice<Event>>
//    var events:ArraySlice<Event>
    
    var body: some View {
        VStack {
            ForEach(events) { event in
                HStack {
                    Text("\(String(event.id!.prefix(5)))")
                    Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: " \(month:  .defaultDigits)-\(day: .defaultDigits)  \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(second: .twoDigits)", timeZone: .current, calendar: .current))
                }
//                NoteRowView(event: event)
//                    .id(event.id)
            }
        }.padding(2)
            .border(.red)
    }
}

struct PaginationTest2_Previews: PreviewProvider {
    static var previews: some View {
        PaginationTest2()
            .withPreviewEnvironment()
    }
}
