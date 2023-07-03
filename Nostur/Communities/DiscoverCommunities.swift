//
//  DiscoverCommunities.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2023.
//

import SwiftUI
import CoreGraphics
import UIKit

struct DiscoverCommunities: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.systemBackground
            VStack {
                Text("Discover Communities", comment: "Heading above list of communities")
            }
        }
        .navigationTitle(String(localized:"Communities", comment: "Navigation title for Communities view"))
    }
}

struct DiscoverCommunities_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverCommunities()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
