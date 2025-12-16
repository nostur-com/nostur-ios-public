//
//  FeedRelaysPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI
import NavigationBackport

struct FeedRelaysPicker: View {
    @Binding var selectedRelays: Set<CloudRelay>
    
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
    
    private var selectedRelaysData: Set<RelayData> {
        Set(selectedRelays.map { $0.toStruct() })
    }
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    var relays: FetchedResults<CloudRelay>
        
    var body: some View {
        NXForm {
            Section(header: Text("Relay selection", comment: "Header for a feed setting")) {
                ForEach(relays, id:\.objectID) { relay in
                    HStack {
                        Image(systemName: selectedRelays.contains(relay) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedRelays.contains(relay) ? Color.primary : Color.secondary)
                        Text(relay.url_ ?? "(Missing relay address)")
                    }
                    .id(relay.objectID)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedRelays.contains(relay) {
                            selectedRelays.remove(relay)
                        }
                        else {
                            selectedRelays.insert(relay)
                        }
                    }
                }
            }
        }
        .navigationTitle("Select relay(s)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var selectedRelays: Set<CloudRelay> = []
    PreviewContainer({ pe in
        pe.loadRelays()
    }) {
        NBNavigationStack {
            if let feed = PreviewFetcher.fetchCloudFeed() {
                FeedRelaysPicker(selectedRelays: $selectedRelays)
            }
        }
    }
}
