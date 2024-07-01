//
//  RelayStats.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/06/2024.
//

import SwiftUI
import NavigationBackport

struct RelayStats: View {
    
    public let stats: [CanonicalRelayUrl: RelayConnectionStats]
    @State private var showingStats: RelayConnectionStats? = nil
    
    var body: some View {
        if stats.isEmpty {
            Text("No stats collected yet.")
        }
        else {
            ScrollView {
                VStack {
                    ForEach(Array(stats.keys), id: \.self) { relayUrl in
                        HStack {
                            Text(relayUrl)
                                .strikethrough(ConnectionPool.shared.penaltybox.contains(relayUrl))
                            Spacer()
                            Text(String(format: "%d/%d/%d", stats[relayUrl]?.connected ?? 0, stats[relayUrl]?.messages ?? 0, stats[relayUrl]?.errors ?? 0))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard stats[relayUrl]?.errors ?? 0 > 0 else { return }
                            showingStats = stats[relayUrl]
                        }
                        Divider()
                    }
                    
                    HStack {
                        Spacer()
                        Text("(Re)connects/Messages/Errors")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(item: $showingStats, content: { relayConnectionStats in
                NBNavigationStack {
                    RelayErrorLog(stats: relayConnectionStats)
                        .navigationTitle(String(localized: "Error messages for \(relayConnectionStats.id)", comment: "Title of relay error messages log sheet"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingStats = nil
                                }
                            }
                        }
                }
                
            })
        }
    }
}

struct RelayErrorLog: View {
    
    public let stats: RelayConnectionStats
    @State private var errorMessages: [String] = []
 
    var body: some View {
        VStack {
            ForEach(errorMessages.indices, id: \.self) { index in
                Text(errorMessages[index])
            }
        }
        .onAppear {
            ConnectionPool.shared.queue.async {
                let lastErrorMessages = stats.lastErrorMessages
                DispatchQueue.main.async {
                    errorMessages = lastErrorMessages
                }
            }
        }
    }
}

#Preview {
    VStack {
        let example: [CanonicalRelayUrl: RelayConnectionStats] = [
            "wss://nos.lol": RelayConnectionStats(id: "wss://nos.lol"),
            "wss://relay.nostr.band": RelayConnectionStats(id: "wss://relay.nostr.band"),
        ]
        
        let _ = example["wss://nos.lol"]?.errors += 1
        let _ = example["wss://nos.lol"]?.errors += 1
        let _ = example["wss://relay.nostr.band"]?.messages += 1
        let _ = example["wss://relay.nostr.band"]?.messages += 1
        
        RelayStats(stats: example)
    }
}
