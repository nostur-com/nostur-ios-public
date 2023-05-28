//
//  ThreadReplies.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/05/2023.
//

import SwiftUI

struct ThreadReplies: View {
    @ObservedObject var nrPost:NRPost
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        LazyVStack {
            ForEach(nrPost.groupedRepliesSorted) { reply in
                PostOrThread(nrPost: reply, grouped:true, rootId: nrPost.id)
            }
            .animation(Animation.spring(), value: nrPost.groupedRepliesSorted)
            Spacer()
        }
        .background(Color("ListBackground"))
        .onAppear {
            nrPost.loadGroupedReplies()
        }
    }
        
}

//struct ThreadReplies_Previews: PreviewProvider {
//    static var previews: some View {
//
//        let exampleId = "e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9"
//
//        NavigationStack {
//            if let example = PreviewFetcher.fetchEvent(exampleId) {
//                let nrPost = NRPost(event: example, withReplyTo: false, withParents: false, withReplies: true, plainText: false)
//                ThreadReplies(nrPost: nrPost)
//            }
//        }
//        .withPreviewEnvironment()
//    }
//}

struct ThreadReplies2_Previews: PreviewProvider {
    static var previews: some View {
        
        let exampleId = "2e7119c8135375060ab0f3e40646869f7337ab86de32574ab1bf57dcd2a93754"
        
        NavigationStack {
            if let example = PreviewFetcher.fetchEvent(exampleId) {
                let nrPost = NRPost(event: example, withReplyTo: false, withParents: false, withReplies: true, plainText: false)
                ScrollView {
                    ThreadReplies(nrPost: nrPost)
                }
            }
        }
        .withPreviewEnvironment()
    }
}
