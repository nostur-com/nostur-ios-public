////
////  PostList.swift
////  Nostur
////
////  Created by Fabian Lachman on 07/03/2023.
////
//import SwiftUI
//import CoreData
//
//struct PostListContainer: View {
//    @Environment(\.managedObjectContext) var viewContext
//    @EnvironmentObject var ns:NosturState
//    @ObservedObject var state = PostListState()
//    
//    var body: some View {
//        PostList(pubkey: ns.account!.publicKey, pubkeys: ns.followingPublicKeys, context: viewContext, lastAppearedId:state.lastAppearedId)
//    }
//}
//
//class PostListState: ObservableObject {
//    @AppStorage("lastAppearedId") var lastAppearedId:String?
//    @AppStorage("lastAppearedCreatedAtInt") var lastAppearedCreatedAtInt:Int?
//    @AppStorage("lastAppearedAtAnchor") var lastAppearedAtAnchor = "BOTTOM"
//    
//    var lastAppearedCreatedAt:Int64 {
//        get { Int64(lastAppearedCreatedAtInt ?? 0) }
//        set { lastAppearedCreatedAtInt = Int(newValue) }
//    }
//}
//
//struct PostList: View {
//    let FETCH_LIMIT = 5000
//    let MAX = 1000
//    @ObservedObject var state = PostListState()
//    
//    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
//    var posts:FetchedResults<Event>
//    var postsNewestAtBottom:[Event] {
//        posts.sorted(by: { $0.created_at < $1.created_at } )
//    }
//    
//    @State var visiblePosts:[Event]?
//    @State var didRestoreState = false // NEED SO USER INITIATED .onAppear is not overwritten by other .onAppear (init, restore)
//    @State var whatHappened = "NOTHING."
//    
//    init(pubkey:String, pubkeys:Set<String>, context:NSManagedObjectContext, lastAppearedId:String?) {
//        UIScrollView.appearance().bounces = false // Needed to not mess up detection of scroll direction
//
//        if let lastAppearedId {
//            let r1 = Event.fetchRequest()
//            r1.predicate = NSPredicate(format: "id == %@", lastAppearedId)
//            r1.fetchLimit = 1
//            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//            
//            
//            // get .created_at of lastAppearedId. OR now if nil
//            let lastAppearedCreatedAt = (try? context.fetch(r1).first?.created_at) ?? Int64(Date.now.timeIntervalSince1970)
//
//            // then fetch posts 8 hours before .created_at, or before now if nil
//            let lastAppearedCreatedAtPlusHours = lastAppearedCreatedAt - (3600 * 24 * 90)
//            
//                
//                                                 
//            let r2 = Event.fetchRequest()
//            r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", lastAppearedCreatedAtPlusHours, pubkeys)
//            r2.fetchLimit = FETCH_LIMIT
//            r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//            _posts = FetchRequest(fetchRequest: r2)
//        }
//        
//        else {
//            let hoursAgo = Int64(Date.now.timeIntervalSince1970) - (3600 * 24 * 90)
//                                                    
//            let r2 = Event.fetchRequest()
//            r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", hoursAgo, pubkeys)
//            r2.fetchLimit = FETCH_LIMIT
//            r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//            _posts = FetchRequest(fetchRequest: r2)
//        }
//        
//        
//        
//    }
//    
////    init(posts:[DummyEvent]) {
////        self.posts = posts
////        UIScrollView.appearance().bounces = false // Needed to not mess up detection of scroll direction
////        whatHappened = whatHappened + "INIT."
////    }
//    
//    var body: some View {
//        VStack {
////            Text(posts.nsPredicate?.description ?? "")
//            Text("w: \(whatHappened) posts.count:\(posts.count)").font(.caption2)
//            Text("visible.count:\(visiblePosts?.count ?? 0)").font(.caption2)
//            Text("didRestoreState: \(didRestoreState.description)")
//            Text("Direction: \(state.lastAppearedAtAnchor) id:\((state.lastAppearedId ?? "").prefix(5).description) at:\(d(state.lastAppearedCreatedAt).description)")
//            if let visiblePosts {
//                ScrollViewReader { proxy in
//                    List(visiblePosts) { post in
//                        NavigationLink(value: post) {
//                            Text("\((post.id).prefix(5).description) \(d(post.created_at).description) \(post.noteText)")
//                                .lineLimit(3)
//                                .onBecomingVisible {
//                                    guard didRestoreState else { return } // Only set last appeared if we already restored, (so not when programmatically .scrollTo)
//                                    setLastAppeared(post)
//                                }
//                        }.id(post.id)
//                    }
//                    .onAppear {
//                        guard !didRestoreState else { return } // Onlyif we didn't restore yet (so not like nav to post and back)
//                        proxy.scrollTo(state.lastAppearedId, anchor: state.lastAppearedAtAnchor == "TOP" ? .top : .bottom)
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            didRestoreState = true
//                        }
//                    }
//                    .navigationDestination(for: DummyEvent.self) { post in
//                        Text("Detail: \(post.id)")
//                            .onAppear {
//                                
//                            }
//                    }
//                }
//            }
//        }
//        .onAppear {
//            guard !didRestoreState else { return } // Only restore state once (so not again at like nav to post and back)
//            setVisiblePosts()
//            whatHappened = whatHappened + "FIRST."
//        }
//        
//    }
//    
//    func setVisiblePosts() {
//        guard state.lastAppearedId != nil else {
//            visiblePosts = postsNewestAtBottom.suffix(MAX) // IF FIRST TIME, SHOW LAST 100
//            return
//        }
//
//        // GET INDEX OF LAST APPEARED POST, PREFIX AND SUFFIX MAX/2
//        guard let lastAppearedIndex = posts.firstIndex(where: { $0.id == state.lastAppearedId! }) else {
//            visiblePosts = postsNewestAtBottom.suffix(MAX) // IF NOT FOUND, SHOW LAST 100
//            return
//        }
//        let startIndex = max(lastAppearedIndex - MAX/2, 0)                  // [MAX/2] BEFORE
////        let endIndex = min(lastAppearedIndex + MAX/2, posts.count - 1)      // [MAX/2] AFTER
//        let endIndex = postsNewestAtBottom.count - 1                                      // INFINITE AFTER
//        visiblePosts = Array(postsNewestAtBottom[startIndex...endIndex])
//    }
//    
//    func setLastAppeared(_ post: Event) {
//        // We need to now, is the last appeared from scrolling up? or down?
//        // So compare createdAt with the previous lastAppeared:
//        state.lastAppearedAtAnchor = post.created_at > state.lastAppearedCreatedAt ? "BOTTOM" : "TOP"
//        state.lastAppearedCreatedAt = post.created_at
//        state.lastAppearedId = post.id
//    }
//}
//
//struct PostList_Previews: PreviewProvider {
//    static var previews: some View {
////        let dummies = (0...1000).map { DummyEvent(id:$0)}
//        NavigationStack {
//            VStack {
////                PostList(posts: dummies)
//                PostListContainer()
//                    .withPreviewEnvironment()
//            }
//        }
//    }
//}
//
//struct DummyEvent: Identifiable, Hashable {
//    let id:String
//    let created_at:Int64
//    init(id:Int) {
//        self.id = String(id)
//        self.created_at = Int64(id)
//    }
//    var text:String {
//        "note: \(id)"
//    }
//}
//
//
//public extension View {
//    func onBecomingVisible(perform action: @escaping () -> Void) -> some View {
//        modifier(BecomingVisible(action: action))
//    }
//}
//
//private struct BecomingVisible: ViewModifier {
//    
//    @State var action:(() -> Void)?
//
//    func body(content: Content) -> some View {
//        content.overlay {
//            GeometryReader { proxy in
//                Color.clear
//                    .preference(
//                        key: VisibleKey.self,
//                        // See discussion!
//                        value: UIScreen.main.bounds.intersects(proxy.frame(in: .global))
//                    )
//                    .onPreferenceChange(VisibleKey.self) { isVisible in
//                        guard isVisible, let action else { return }
//                        action()
////                        action = nil
//                    }
//            }
//        }
//    }
//
//    struct VisibleKey: PreferenceKey {
//        static var defaultValue: Bool = false
//        static func reduce(value: inout Bool, nextValue: () -> Bool) { }
//    }
//}
