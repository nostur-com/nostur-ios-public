//
//  AddRelayFeedSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/08/2025.
//

import SwiftUI
import NavigationBackport

struct AddRelayFeedSheet: View {
    public var relay: String
    var body: some View {
        Text("Hello")
            .navigationTitle("Relay preview")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NBNavigationStack {
        AddRelayFeedSheet(relay: "wss//nos.lol")
    }
}
