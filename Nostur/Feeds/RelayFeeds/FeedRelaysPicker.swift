//
//  FeedRelaysPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct FeedRelaysPicker: View {
    @Binding var selectedRelays: Set<CloudRelay>
    
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
    @State private var newRelayUrl = ""
    
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

            Section("Add relay") {
                TextField("wss://relay.example.com", text: $newRelayUrl)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button("Add relay", systemImage: "plus") {
                    addRelay()
                }
                .disabled(!newRelayUrl.lowercased().hasPrefix("wss://") && !newRelayUrl.lowercased().hasPrefix("ws://"))
            }
        }
        .navigationTitle("Select relay(s)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addRelay() {
        let normalizedUrl = normalizeRelayUrl(newRelayUrl.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedUrl.isEmpty else { return }

        if let existingRelay = relays.first(where: { normalizeRelayUrl($0.url_ ?? "") == normalizedUrl }) {
            selectedRelays.insert(existingRelay)
        }
        else {
            let relay = CloudRelay(context: viewContext())
            relay.url_ = normalizedUrl
            relay.read = false
            relay.write = false
            relay.createdAt = .now
            selectedRelays.insert(relay)
        }
        newRelayUrl = ""
        DataProvider.shared().saveToDiskNow(.viewContext)
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
