//
//  PaginationTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

// DEZE IS GOED.. MAAR 3 x REVERSE..!!

import SwiftUI
import CoreData

var ddd = 453

struct PageModel {
    var id:String // index + events.count
    var events:Slice<FetchedResults<Event>>?
}

struct PaginationTest3: View {
    @Namespace var SCROLLANCHOR
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest
    var events: FetchedResults<Event>
    @State var pages: [PageModel] = []
    let pageSize = 1
    
    init() {
//        UIScrollView.appearance().bounces = false
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
        fr.fetchLimit = 20
        _events = FetchRequest(fetchRequest: fr)
    }
    
    func scrollTo(_ proxy:ScrollViewProxy) {
        proxy.scrollTo(SCROLLANCHOR)
    }
    
    var body: some View {
NavigationStack {
    //        ScrollViewReader { proxy in
                ScrollView {
    //                Color.clear.frame(width: 200, height: 0).id(SCROLLANCHOR)
                    LazyVStack {
                        ForEach(pages.reversed(), id:\.id) { page in
                            BPage(id:page.id, events: page.events)
                                .id(page.id)
    //                            .scaleEffect(x: 1, y: -1)
                        }
                    }
                }
    //            .scaleEffect(x: 1, y: -1)
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        HStack {
                            Spacer()
                            VStack {
                                //                    Rectangle().frame(width: 30, height: 100)
                                HStack {
                                    Text("EVENTS: \(events.count) PAGES:\(pages.count)")
                                    Button {
                                        print("🚘 ADDING EVENTS")
                                        for _ in 0..<1 {
                                            let newEvent = Event(context: viewContext)
                                            newEvent.id = UUID().description
                                            newEvent.kind = 1
                                            newEvent.pubkey = "1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170"
                                            newEvent.created_at = Int64(Date.now.timeIntervalSince1970)
                                        }
                                    } label: { Text("Add events") }
                                    Button { updatePages() } label: { Text("Update Pages") }
    //                                Button { scrollTo(proxy) } label: { Text("To Top") }
                                }
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                        }.background(.regularMaterial)
                    }
                }
                .onAppear { setupPages() }
    //        }
}
    }
    
    let placeholderPages = 50
    
    func setupPages() {
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<11
            let events = events.dropLast(loopCount * pageSize).suffix(pageSize)
            let page = PageModel(id: "\(loopCount)-\(events.count)", events: events)
            pages.append(page)
        }
        let emptyPages = placeholderPages - pageCount
        for i in 0..<emptyPages {
            pages.append(PageModel(id: "\(pageCount + i)-EMPTY"))
        }
    }
    func updatePages() {
        let beforeEventsCount = pages.reduce(0) { partialResult, page in
            return partialResult + (page.events?.count ?? 0)
        }
//        if (events.count != beforeEventsCount) { // TODO: should check 'gt' also?
//            vm.pendingHeightChange = true
//            print("🚘 PENDING HEIGHT CHANGE FLAG ADDED")
//        }
        
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        // All pages // TODO: HOw only update/add pages, leave existing in tact..
        for loopCount in 0..<pageCount { // 0..<11
            if (loopCount < beforeEventsCount) { continue }
            let events = events.dropLast(loopCount * pageSize).suffix(pageSize)
            let page = PageModel(id: "\(loopCount)-\(events.count)", events: events)
            pages[loopCount] = page
        }
        let emptyPages = placeholderPages - pageCount
        for i in 0..<emptyPages {
            pages[pageCount + i] = PageModel(id: "\(pageCount + i)-EMPTY")
        }
    }
}

var rr = 34

struct BPage: View {
    var id:String
    var events:Slice<FetchedResults<Event>>?
    //    var events:ReversedCollection<Slice<FetchedResults<Event>>>
    //    var events:ReversedCollection<ArraySlice<Event>>
    //    var events:ArraySlice<Event>
    
    let t = ["06dac": "A", "26a7d":"B", "27266":"C", "1b2a9":"D", "863a8":"E", "49bea":"F", "04265":"G", "f79f6":"H", "2d5b8":"I", "143ef":"J"]
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            if (events == nil) {
                Color.red.frame(width: 200, height: 10)
            }
            else {
                ForEach(events!) { event in
//                                        HStack {
//                                            //                    Text("\(String(event.id!.prefix(5)))")
//                                            if let pd = t[String(event.id!.prefix(5))] {
//                                                Text("\(pd)").font(.largeTitle)
//                                            }
//                                            else {
//                                                Text("\(String(event.id!.prefix(5)))").font(.largeTitle)
//                                            }
//                                            Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: " \(month:  .defaultDigits)-\(day: .defaultDigits)  \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(second: .twoDigits)", timeZone: .current, calendar: .current)).font(.largeTitle)
//                                        }.border(.green)
                    VStack {
                        Text("PAGE ID: \(id)")
                        NoteRowView(event: event)
                            .id(event.id)
                    }
                }
            }
        }.padding(2).background(Color.random)
    }
}

struct PaginationTest3_Previews: PreviewProvider {
    static var previews: some View {
        PaginationTest3()
            .withPreviewEnvironment()
    }
}
