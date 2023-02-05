//
//  PaginationTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

// DEZE IS GOED.. MAAR 3 x REVERSE..!!

import SwiftUI
import CoreData
import Combine

extension PaginationTest3 {
    @MainActor class PaginationTest3ViewModel: ObservableObject {
        @Published var topAnchorSize = CGFloat.zero
        @Published var bottomAnchorSize = CGFloat.zero
        
        @Published var pendingHeightChange = false
        
        @Published private(set) var topOffset = CGFloat.zero // = scrollOffset
        @Published private(set) var bottomOffset = CGFloat.zero
        @Published private(set) var contentHeight = CGFloat.zero
        @Published private(set) var viewportHeight = CGFloat.zero
        
        @Published private(set) var scrollCounter = 0
        
        func triggerScroll() {
            self.scrollCounter = self.scrollCounter + 1
        }
        
        func moveAnchorUp() {
            self.topAnchorSize = self.topAnchorSize - 50
            self.bottomAnchorSize = self.bottomAnchorSize - 50
        }
        
        @Published private(set) var viewportOffsetTopEmitter = PassthroughSubject<CGFloat, Never>()
//        @Published private(set) var viewportOffsetBottomEmitter = PassthroughSubject<CGFloat, Never>()
        @Published private(set) var contentHeightEmitter = PassthroughSubject<CGFloat, Never>()
        @Published private(set) var viewportHeightEmitter = PassthroughSubject<CGFloat, Never>()
        
        var cancellables = Set<AnyCancellable>()
        
        init() {
            addSubscribers()
        }
        
        func finish() {
            self.pendingHeightChange = false
            print("🚘 PENDING HEIGHT CHANGE FLAG REMOVED")
        }
        
        func addSubscribers() {
            viewportOffsetTopEmitter
//                .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
                .sink { topOffset in
                    if (!self.pendingHeightChange) {
                        self.topOffset = topOffset
                        self.topAnchorSize = -topOffset
                        self.bottomAnchorSize = self.contentHeight - self.viewportHeight - -topOffset
                    }
                }
                .store(in: &cancellables)
            
//            viewportOffsetBottomEmitter
////                .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
//                .sink { bottomOffset in
//                    if (!self.pendingHeightChange) {
//                        self.bottomOffset = bottomOffset
//                        // KEEP ANCHOR IN SYNC
//                        //                        self.anchorSize = value + 50 // +30 to "see" anchor
//                        self.bottomAnchorSize = self.contentHeight - bottomOffset + self.topOffset
//                    }
//                }
//                .store(in: &cancellables)
            
            contentHeightEmitter
                .sink { contentHeight in
                    if (self.pendingHeightChange) {
//                        self.topAnchorSize = self.topOffset
                        // hier self.pendingHeightChange = false?
                        print("🚘 NEW HEIGHT: \(contentHeight). BOTTOM ANCHOR CHANGED FROM: \(self.bottomAnchorSize) TO: \(self.bottomAnchorSize - (contentHeight - self.contentHeight) - self.topOffset)")
                        self.bottomAnchorSize = self.bottomAnchorSize - (contentHeight - self.contentHeight) - self.topOffset
                    }
                    else {
                        print("🚘 HEIGHT CHANGE IGNORED \(contentHeight)")
                    }
                    self.contentHeight = contentHeight
                }
                .store(in: &cancellables)
            
            viewportHeightEmitter
                .sink { viewportHeight in
                    if (self.pendingHeightChange) {
//                        self.topAnchorSize = self.topOffset
//                        self.bottomAnchorSize = value - self.bottomOffset
                    }
                    self.viewportHeight = viewportHeight
                }
                .store(in: &cancellables)
        }
    }
}

struct ViewportOffsetTop: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
struct ViewportOffsetBottom: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
struct ViewportHeightKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

struct PaginationTest3: View {
    @Namespace var TOP_SCROLL_ANCHOR
    @Namespace var BOTTOM_SCROLL_ANCHOR
    @Namespace var SCROLL_SPACE
    
    @StateObject var vm = PaginationTest3ViewModel()
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest
    var events: FetchedResults<Event>
    @State var pages: [Slice<FetchedResults<Event>>] = []
    let pageSize = 3
    
    init() {
        UIScrollView.appearance().bounces = false
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
        fr.fetchLimit = 20
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack { // ZSTACK WITH 2 LAYERS: PAGES, ANCHOR.
                    LazyVStack {
                        ForEach(pages.reversed(), id:\.startIndex) { events in
                            BPage(events: events)
                        }
                    }
                    VStack(spacing: 0) { // THE SCROLL ANCHOR
                        Rectangle().foregroundColor(.purple).opacity(0.3).frame(width:370, height: vm.topAnchorSize < 0 ? 0 : vm.topAnchorSize).foregroundColor(.purple)
                        Color.purple.frame(width: 370, height: 3)
                            .id(TOP_SCROLL_ANCHOR)
                        Spacer()
                        Color.green.frame(width: 370, height: 3)
                            .id(BOTTOM_SCROLL_ANCHOR)
                        Rectangle().foregroundColor(.green).opacity(0.3).frame(width:370, height: vm.bottomAnchorSize < 0 ? 0 : vm.bottomAnchorSize).foregroundColor(.green)
                    }
                }
                // SEND TO PARENT: SCROLL OFFSET + CONTENT HEIGHT
                .background(GeometryReader { contentGeo in
                    Color.clear.preference(
                        key: ViewportOffsetTop.self,
                        value: contentGeo.frame(in: .named(SCROLL_SPACE)).minY
                    )
//                    .preference(
//                        key: ViewportOffsetBottom.self,
//                        value: contentGeo.frame(in: .named(SCROLL_SPACE)).maxY
//                    )
                    .preference(
                        key: ContentHeightKey.self,
                        value: contentGeo.size.height
                    )
                })
                // RECEIVE FROM CHILD: SCROLL OFFSET + CONTENT HEIGHT
                .onPreferenceChange(ViewportOffsetTop.self) { offset in
                    vm.viewportOffsetTopEmitter.send(offset)
                }
//                .onPreferenceChange(ViewportOffsetBottom.self) { offset in
//                    vm.viewportOffsetBottomEmitter.send(offset)
//                }
                // RECEIVE FROM CHILD: CONTENT HEIGHT
                .onPreferenceChange(ContentHeightKey.self) { height in
                    vm.contentHeightEmitter.send(height)
                }
                .onChange(of: vm.bottomAnchorSize) { newValue in
                    if (vm.pendingHeightChange) {
                        vm.finish()
                        print("🚘 SCROLLING TO BOTTOM ANCHOR")
                        proxy.scrollTo(BOTTOM_SCROLL_ANCHOR)
                    }
                }
                .onChange(of: vm.scrollCounter) { newValue in
                    withAnimation {
                        print("🚘 SCROLLING TO BOTTOM ANCHOR")
                        proxy.scrollTo(BOTTOM_SCROLL_ANCHOR)
                    }
                }
            }
            .background(GeometryReader { viewPortGeo in
                Color.clear.preference(
                    key: ViewportHeightKey.self,
                    value: viewPortGeo.size.height
                )
            })
            .onPreferenceChange(ViewportHeightKey.self) { height in
                vm.viewportHeightEmitter.send(height)
            }
        }
        //            .ignoresSafeArea(edges: .top)
        .coordinateSpace(name: SCROLL_SPACE)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                VStack {
                    Rectangle().frame(width: 30, height: 100)
                    Text("E:\(events.count) TOP OFFSET: \(Int(vm.topOffset)) ANCHOR: \(Int(vm.topAnchorSize))")
                    Text("VIEWPORT HEIGHT: \(Int(vm.viewportHeight)) ANCHOR: \(Int(vm.bottomAnchorSize))")
                    Text("CONTENT HEIGHT: \(Int(vm.contentHeight))")
                    HStack {
                        Button {
                            print("🚘 ADDING 1 EVENT AT HEIGHT: \(vm.contentHeight)")
                            let newEvent = Event(context: viewContext)
                            newEvent.id = UUID().description
                            newEvent.kind = 1
                            newEvent.created_at = Int64(Date.now.timeIntervalSince1970)
                        } label: { Text("Add event") }
                        Button { updatePages() } label: { Text("Pages") }
                        Button { vm.triggerScroll() } label: { Text("Scroll") }
                        Button { vm.moveAnchorUp() } label: { Text("Move") }
                        Button { vm.pendingHeightChange.toggle() } label: { Text("T") }
                    }
                }.buttonStyle(.borderedProminent)
                Spacer()
            }.background(.regularMaterial)
        }
        .onChange(of: events.first) { newestEvent in
            //            updatePages()
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
        // DIFF (40) CURRENT HEIGHT (890), NEW HEIGHT (830)
        // SHOULD BE ADDED TO ANCHOR
        // THEN SCROLL TO
        // THEN RESET OR PREVENT SCROLL OFFSET CONFLICTING WITH NEW ANCHOR HEIGHT
        
        // SET PENDING HEIGHT CHANGE FLAG IF THERE ARE NEW EVENTS
        let beforeEventsCount = pages.reduce(0) { partialResult, events in
            return partialResult + events.count
        }
        if (events.count != beforeEventsCount) { // TODO: should check 'gt' also?
            vm.pendingHeightChange = true
            print("🚘 PENDING HEIGHT CHANGE FLAG ADDED")
        }
        
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        pages = []
        // All pages // TODO: HOw only update/add pages, leave existing in tact..
        for loopCount in 0..<pageCount { // 0..<11
            pages.append(events.dropLast(loopCount * pageSize).suffix(pageSize))
        }
        // NEW HEIGHT IS NOT KNOWN HERE YET..
        // SO. FLAG FOR PENDING HEIGHT CHANGE
        // ON HEIGHT CHANGE DO THINGS IF FLAG IS SET
        print("🚘 UPDATED PAGES (MODEL), NEW HEIGHT: \(vm.contentHeight) (VIEW NOT UPDATED YET)")
    }
}

var rr = 3

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
                        Text("\(pd)").font(.largeTitle)
                    }
                    else {
                        Text("\(String(event.id!.prefix(5)))").font(.largeTitle)
                    }
                    Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: " \(month:  .defaultDigits)-\(day: .defaultDigits)  \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(second: .twoDigits)", timeZone: .current, calendar: .current)).font(.largeTitle)
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
