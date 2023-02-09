//
//  PaginationTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

// DEZE IS GOED.. MAAR 3 x REVERSE..!!

import SwiftUI
import CoreData
import Introspect
import Combine



struct PaginationTest3: View {
    
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest
    var events: FetchedResults<Event>
    @State var notes: [Event] = []
    
    @State private var scroller: UIScrollView?
    
    init() {
        UIScrollView.appearance().bounces = false
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.insertedAt, ascending: false), NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 1")
        fr.fetchLimit = 10
        _events = FetchRequest(fetchRequest: fr)
    }
    
    @State var contentHeight = 0.0
    @State var oldContentHeight = 0.0
    @State var pendingHeightChange = false
    
    var body: some View {
        VStack {
            List(notes.indices, id:\.self) { index in
                Text("index:\(notes[index].noteId)\n\(d(notes[index].created_at).description)").background(randomColor(seed: notes[index].noteId).frame(width:300,height:100)).frame(width: 300, height: 100)
//                NoteRowView(event: notes[index])
                    .id(notes[index].noteId)
                    .listRowInsets(EdgeInsets())
            }
            //            .didScroll { contentOffset in
            //                print(contentOffset)
            //            }
            .didChangeHeight { contentHeight in
                print(contentHeight)
                offset = scroller!.contentOffset.y
                self.contentHeight = contentHeight
                if (pendingHeightChange) {
                    if (scroller != nil) {
//                        scroller!.layoutIfNeeded()
                        scroller!.contentOffset.y = oldOffset + (contentHeight - oldContentHeight)
                        pendingHeightChange = false
                        oldContentHeight = contentHeight
                    }
                }
            }
            .listStyle(.plain)
            /* in iOS 16 List is backed by UICollectionView, no out of the box .introspectMethod ... nbd. */
            .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
                guard #available(iOS 16, *) else { return }
                self.scroller = collectionView
                var config = UICollectionLayoutListConfiguration(appearance: .plain)
                config.showsSeparators = false
                
                let layout = UICollectionViewCompositionalLayout.list(using: config)
                
                collectionView.collectionViewLayout = layout
            })
            
            /* in iOS 15 List is backed by UITableView ... */
            .introspectTableView(customize: { tableView in
                guard #available(iOS 15, *) else { return }
                self.scroller = tableView
            })
            
            
            Text("\(notes.count)")
            //            UIList(notes: $notes)
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        HStack {
                            Text("offset: \(offset)")
                            Text("contentHeight: \(contentHeight)")
                            Spacer()
                            VStack {
                                Button {
                                    viewContext.performAndWait {
                                        try! ns.loadActiveAccount()
                                        for _ in 0..<1 {
                                            var nEvent = NEvent(content: "test1")
                                            var s = try! ns.signEvent(nEvent)
                                            
                                            let newEvent = Event(context: viewContext)
                                            newEvent.id = s.id
                                            newEvent.kind = 1
                                            newEvent.pubkey = s.publicKey
                                            newEvent.created_at = Int64(s.createdAt.timestamp)
                                            newEvent.insertedAt = Date.now
                                        }
                                    }
                                } label: { Text("Fetch event \(events.count)") }
                                
                                Button { updatePages() } label: { Text("Update view") }
                                
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                        }.background(.regularMaterial)
                    }
                }
                .onAppear { setupPages() }
        }
        
    }
    
    func setupPages() {
        
        let oldestAtIndexZero = events.sorted(by: { $0.created_at > $1.created_at })
            .sorted(by: { $0.insertedAt > $1.insertedAt })
        for index in 0..<events.count {
            notes.insert(oldestAtIndexZero[index], at:0)
        }
        
        oldestAtIndexZero.forEach { event in
            print("\(event.id!) \(d(event.created_at))")
        }
    }
    
    @State var offset = 0.0
    @State var oldOffset = 0.0
    
    func updatePages() {
        
        oldOffset = scroller!.contentOffset.y
        offset = scroller!.contentOffset.y
        oldContentHeight = contentHeight
        pendingHeightChange = true
        
        // Calculate the distance of the tableView
        // from the current content offset to the end of the content size
        //            self.scroller!.layoutIfNeeded()
        //            let heightBefore = self.scroller!.contentSize.height
        //            var transaction = Transaction(animation: .none)
        //                          transaction.disablesAnimations = true
        //
        //                          withTransaction(transaction) {
        
        
        let oldestAtIndexZero = events.sorted(by: { $0.created_at > $1.created_at })
            .sorted(by: { $0.insertedAt > $1.insertedAt })
        let beforeEventsCount = notes.count
        for index in 0..<(events.count-notes.count) { // 0..<11
//            if (index < beforeEventsCount) { continue }
            //            notes.insert(oldestAtIndexZero[index],at:0)
            notes.insert(oldestAtIndexZero[index], at:0)
            
            // 0, 1, 2, 3, 4, 5, 6, 7
            // N, N, 0, 1, 2, 3, 4, 5
        }
        //            oldestAtIndexZero.forEach { event in
        //                print("\(event.id!) \(d(event.created_at))")
        //            }
        
        //                              let newOffset = self.scroller!.contentSize.height - heightBefore + scroller!.contentOffset.y
        //                              self.scroller!.layoutIfNeeded()
        //                              // set new content offset for the tableview without animation
        //                              self.scroller!.setContentOffset(CGPoint(x: 0, y: newOffset), animated: true)
        
        
        //                          }
        
        //            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
        //                // Calculate new content offset after reload tableView
        //                let newOffset = self.scroller!.contentSize.height - heightBefore + scroller!.contentOffset.y
        //                self.scroller!.layoutIfNeeded()
        //                // set new content offset for the tableview without animation
        //                self.scroller!.setContentOffset(CGPoint(x: 0, y: newOffset), animated: true)
        //            }
        
        oldestAtIndexZero.forEach { event in
            print("\(event.id!) \(d(event.created_at))")
        }
    }
}

struct PaginationTest3_Previews: PreviewProvider {
    static var previews: some View {
        PaginationTest3()
            .withPreviewEnvironment()
    }
}

var rfrr = 334433
