//
//  SmoothListAttempt382.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/05/2023.
//

import SwiftUI

struct SmoothListAttempt382: View {
    let nrPosts:[NRPost]
    
    var body: some View {
        List(nrPosts) { nrPost in
            PostOrThread(nrPost: nrPost)
        }
    }
}

struct SmoothListAttempt382_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VStack {
                let ns:NosturState = .shared
                let events = PreviewFetcher.fetchEvents(ns.followingPublicKeys, kind: 1)
                
                let onlyRootEvents = events
                    .map {
                        $0.parentEvents = Event.getParentEvents($0)
                        return $0
                    }
                    .filter(onlyRootOrReplyingToFollower)
                
                let nrPosts = onlyRootEvents.compactMap { NRPost(event: $0) }
                
                SmoothListAttempt382(nrPosts: nrPosts)
            }
        }
        .withPreviewEnvironment()
    }
}
