//
//  PaginationTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

// DEZE IS GOED.. MAAR 3 x REVERSE..!!

import SwiftUI
import CoreData

struct PaginationTest3: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest
    var events: FetchedResults<Event>

    @State var pages: [Slice<FetchedResults<Event>>] = []
//    @State var pages: [ArraySlice<Event>] = []
    
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
                    BPage(events: events)
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
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<11
            pages.append(events.dropLast(loopCount * pageSize).suffix(pageSize))
        }
    }
    func updatePages() {
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        pages = []
        // All pages // TODO: HOw only update/add pages, leave existing in tact..
        for loopCount in 0..<pageCount { // 0..<11
            pages.append(events.dropLast(loopCount * pageSize).suffix(pageSize))
        }
    }
}

struct BPage: View {
    
    var events:Slice<FetchedResults<Event>>
//    var events:ReversedCollection<Slice<FetchedResults<Event>>>
//    var events:ReversedCollection<ArraySlice<Event>>
//    var events:ArraySlice<Event>
    
    let t = ["06dac": "A", "26a7d":"B", "27266":"C", "1b2a9":"D", "863a8":"E", "49bea":"F", "04265":"G", "f79f6":"H", "2d5b8":"I", "143ef":"J"]
    
    var body: some View {
        
        VStack {
            ForEach(events) { event in
                HStack {
//                    Text("\(String(event.id!.prefix(5)))")
                    if let pd = t[String(event.id!.prefix(5))] {
                        Text("\(pd)")
                    }
                    else {
                        Text("\(String(event.id!.prefix(5)))")
                    }
                    Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: " \(month:  .defaultDigits)-\(day: .defaultDigits)  \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(second: .twoDigits)", timeZone: .current, calendar: .current))
                }
//                NoteRowView(event: event)
//                    .id(event.id)
            }
        }.padding(2)
            .border(.red)
    }
}

struct PaginationTest3_Previews: PreviewProvider {
    static var previews: some View {
        PaginationTest3()
            .withPreviewEnvironment()
    }
}
