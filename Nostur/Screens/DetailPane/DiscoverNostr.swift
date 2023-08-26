//
//  DiscoverNostr.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/08/2023.
//

import SwiftUI

struct DiscoverNostr: View {
    var body: some View {
        HStack {
            VStack(spacing: 20) {
                Text("Discover Nostr")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    
                Group {
                    HStack {
                        Text("[#coffeechain](nostur:t:coffeechain)")
                        Text("[#nostr](nostur:t:nostr)")
                        Text("[#foodstr](nostur:t:foodstr)")
                    }
                    HStack {
                        Text("[#footstr](nostur:t:footstr)")
                        Text("[#zapathon](nostur:t:zapathon)")
                        Text("[#music](nostur:t:music)")
                    }
                    HStack {
                        Text("[#asknostr](nostur:t:asknostr)")
                        Text("[#beerstr](nostur:t:beerstr)")
                        Text("[#winestr](nostur:t:winestr)")
                    }
                    HStack {
                        Text("[#bitcoin](nostur:t:bitcoin)")
                        Text("[#grownostr](nostur:t:grownostr)")
                        Text("[#memes](nostur:t:memes)")
                    }
                }
                .lineLimit(1)
                .font(.title)
            }
        }
        .padding()
    }
}

struct DiscoverNostr_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverNostr()
    }
}
