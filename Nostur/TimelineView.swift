//
//  TimelineView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct TimelineView: View {
    
    var tweets : Array<Tweet>
    
    var body: some View {
        ScrollView {
            VStack {
                LazyVStack {
                    ForEach(tweets) { tweet in
                        TweetView(tweet: tweet)
                    }
                }.padding(.vertical)
                Spacer()
            }
        }
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView(tweets:DummyTweets().tweets())
    }
}
