//
//  GossipTesting.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/06/2023.
//

import SwiftUI

struct GossipTesting: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct GossipTesting_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadContacts() }) {
            GossipTesting()
        }
    }
}
