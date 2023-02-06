//
//  PaginationTest4.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/02/2023.
//
// Test met (seemingly) infinite LazyVStack in both directions

import SwiftUI
import CoreData

struct PPageModel {
    var id:String // index + events.count
    var events:Slice<FetchedResults<Event>>
}

struct PaginationTest4: View {
    @Namespace var SCROLLANCHOR
    @Environment(\.managedObjectContext) var viewContext
    
    var events: FetchedResults<Event>
    var indices: [Event]
//    var placeholderIndices = [0...1000]
    let placeholderIndices = [Int](0...1000)
    
    init(events:FetchedResults<Event>) {
        self.events = events
        indices = Array(events)
        //        UIScrollView.appearance().bounces = false
        
//        let shift = 5
//        /// 0 is very first, 500 is center .. 1000 is olders
//        for rowIndex in 0...1000 {
//            if (rowIndex-shift >= events.startIndex && rowIndex-shift < events.endIndex) {
//                infiniteVStack.insert(PossibleNote(rowIndex: rowIndex, event: events[rowIndex-shift]), at: rowIndex)
//            }
//            else {
//                infiniteVStack.insert(PossibleNote(rowIndex: rowIndex), at: rowIndex)
//            }
//
//        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(placeholderIndices, id:\.self) { index in
                    HStack {
                        if indices.count > index {
                            DebugNote(event: indices[index])
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 0)
                        }
                    }
                }
            }
        }.safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    print("🚘 ADDING EVENTS")
                    for _ in 0..<3 {
                        let newEvent = Event(context: viewContext)
                        newEvent.id = UUID().description
                        newEvent.kind = 1
                        newEvent.pubkey = "1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170"
                        newEvent.created_at = Int64(Date.now.timeIntervalSince1970)
                    }
                } label: { Text("Add events") }
                Spacer()
            }.background(.regularMaterial)
        }
    }
    
    func setupPages() {
        
    }
    func updatePages() {
    }
}

struct PossibleNote {
    var rowIndex:Int
    var event:Event?
}

struct DebugNote: View {
    var event:Event
    
    let t = ["06dac": "A", "26a7d":"B", "27266":"C", "1b2a9":"D", "863a8":"E", "49bea":"F", "04265":"G", "f79f6":"H", "2d5b8":"I", "143ef":"J"]
    
    var body: some View {
        HStack {
            if let pd = t[String(event.id!.prefix(5))] {
                Text("\(pd)").font(.largeTitle)
            }
            else {
                Text("\(String(event.id!.prefix(5)))").font(.largeTitle)
            }
            Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: " \(month:  .defaultDigits)-\(day: .defaultDigits)  \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(second: .twoDigits)", timeZone: .current, calendar: .current)).font(.largeTitle)
                
        }
    }
}

struct Wrappah: View {
    @FetchRequest
    var events: FetchedResults<Event>
    
    init() {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
        fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
        fr.fetchLimit = 5
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        PaginationTest4(events: events)
    }
}

struct PaginationTest4_Previews: PreviewProvider {
    static var previews: some View {
        Wrappah()
            .withPreviewEnvironment()
    }
}
