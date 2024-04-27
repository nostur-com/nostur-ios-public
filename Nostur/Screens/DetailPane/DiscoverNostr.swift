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
                        Text(verbatim: "[#coffeechain](nostur:t:coffeechain)")
                        Text(verbatim: "[#nostr](nostur:t:nostr)")
                        Text(verbatim: "[#foodstr](nostur:t:foodstr)")
                    }
                    HStack {
                        Text(verbatim: "[#footstr](nostur:t:footstr)")
                        Text(verbatim: "[#zapathon](nostur:t:zapathon)")
                        Text(verbatim: "[#music](nostur:t:music)")
                    }
                    HStack {
                        Text(verbatim: "[#asknostr](nostur:t:asknostr)")
                        Text(verbatim: "[#beerstr](nostur:t:beerstr)")
                        Text(verbatim: "[#winestr](nostur:t:winestr)")
                    }
                    HStack {
                        Text(verbatim: "[#bitcoin](nostur:t:bitcoin)")
                        Text(verbatim: "[#grownostr](nostur:t:grownostr)")
                        Text(verbatim: "[#memes](nostur:t:memes)")
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
