////
////  ReversedTimeline.swift
////  Nostur
////
////  Created by Fabian Lachman on 01/02/2023.
////
//
//import SwiftUI
//import CoreData
//import Combine
//
//
//// FETCHED REQUEST
//struct Timeline2: View {
//
//    @State var isLoading = true
//
//
//
//
//
//
//
//    @AppStorage("lastReadDate") var lastReadDate = 0
//    @State var didAutoScroll = false // Only scroll to last unread after launch, not after .onAppear after coming back from detail
//
//    @State var lastReadIndex = 0
//    @State var watchForHeightChange = false
//
//
//
//
// 
//}
//
//
//
//
//
//
//extension Timeline2 {
//
//    private func importNotes() {
//        //        print("💿💿 2. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE IMPORT events.count: \(events.count)")
//        Task { await Importer.shared.importEvents() }
//    }
//
//    private func fetchNotes() async {
//        //        isRefreshing = true
//        fetchEventsFromFollowing(amount:500)
//        //TODO: hmmm need to return earlier if onChange events.last
//        try! await Task.sleep(nanoseconds: 1_000_000_000)
//        //        isRefreshing = false
//    }
//
//
//}
//
//struct Timeline_Previews: PreviewProvider {
//
//    @State static var pubkeys = Set(["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
//                                     "743416b4943b20b8e1ed6c6d8fc81bbb7a27797c4cd3acafae4cc3d1ed67dd4d","4742221ccfbe3bee6d5823715df6864ec45dd8e6bf619527463716fe79a06427","460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","56a6b75373c8f7b93c53bcae86d8ffbaba9f2a1b38122054fcdb7f3bf645b727","0f65aa4d25518263873889f3047fd5e218d33b32d864e8a211d9c04522fd311d","4eb88310d6b4ed95c6d66a395b3d3cf559b85faec8f7691dafd405a92e055d6d", "4eb88310d6b4ed95c6d66a395b3d3cf559b85faec8f7691dafd405a92e055d6d"])
//
//    static var previews: some View {
//
////        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
////
//
//
//        Timeline()
//            .withPreviewEnvironment()
//
//    }
//}
