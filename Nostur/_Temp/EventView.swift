//
//  EventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/01/2024.
//

import SwiftUI
import CoreData
import Combine

struct EventView: View {
    
    @ObservedObject public var eventModel: EventViewModel
    public var viewUpdates: ViewUpdates
    
    var body: some View {
        HStack(alignment: .top) {
            Text(eventModel.pfpUrl ?? "?")
            Text(eventModel.name ?? "?")
            Text("Is bookmarked: \(eventModel.isBookmarked ? "YES" : "NO")")
        }
        .onReceive(viewUpdates.profileUpdates, perform: { update in
            guard eventModel.isRelevantUpdate(update) else { return }
            eventModel.applyUpdate(update)
        })
        .onReceive(viewUpdates.bookmarkUpdates, perform: { update in
            guard eventModel.isRelevantUpdate(update) else { return }
            eventModel.applyUpdate(update)
        })
    }
}

struct AppTest: View {
    
    @State private var viewUpdates = ViewUpdates.shared
    
    var body: some View {
        VStack {
            Button("Mock Profile update", action: sendMockProfileUpdate)
            Button("Mock Bookmark update", action: sendMockBookmarkUpdate)
            EventView(
                eventModel: EventViewModel(
                    id: "3a72941da6030f155b6e5209e96057aec77ab3851a60bce61a36227c327c5322",
                    pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                    name: "Fabian",
                    pfpUrl: "fabian.jpg"
                ),
                viewUpdates: viewUpdates
            )
        }
    }
    
    private func sendMockProfileUpdate() {
        viewUpdates.sendMockProfileUpdate()
    }
    
    private func sendMockBookmarkUpdate() {
        viewUpdates.sendMockBookmarkUpdate()
    }
}

#Preview {
    AppTest()
}






