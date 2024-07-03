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
    
    @State private var statsSorted: [RelayConnectionStats] = []
    
    var body: some View {
        Form {
            if statsSorted.isEmpty {
                Text("No stats collected yet.")
            }
            else {
                Section {
                    ForEach(statsSorted) { relayStats in
                        RelayStatsRow(stats: relayStats)
                            .id(relayStats.id)
                            .drawingGroup()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard relayStats.errors > 0 || relayStats.receivedPubkeys.count > 0 else { return }
                            showingStats = relayStats
                        }
                    }
                } footer: {
                    HStack {
                        Spacer()
                        Text("(Re)connects/Messages/Errors")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            statsSorted = stats.values
                .sorted(by: { $0.errors < $1.errors })
                .sorted(by: { $0.receivedPubkeys.count > $1.receivedPubkeys.count })
                .sorted(by: { $0.connected != 0 && $1.connected == 0 })
        }
        .sheet(item: $showingStats, content: { relayConnectionStats in
            NBNavigationStack {
                RelayStatsDetails(stats: relayConnectionStats)
                    .navigationTitle(relayConnectionStats.id)
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

struct RelayStatsRow: View {
    public let stats: RelayConnectionStats
    
    @State private var foundAccountRows: [(pubkey: String, pfp: URL?, name: String)] = []
    @State private var statsString = ""
    
    var body: some View {
        HStack {
            Text(stats.id)
                .strikethrough(ConnectionPool.shared.penaltybox.contains(stats.id))
                .lineLimit(1)
                .layoutPriority(2)
            
            FoundAccountPFPs(foundAccountRows: foundAccountRows)
                .layoutPriority(1)
            
            Spacer()
            Text(statsString)
                .lineLimit(1)
                .layoutPriority(3)
        }
        .onAppear {
            foundAccountRows = Array(stats.receivedPubkeys
                .filter { pubkey in // We only care about pubkeys we follow
                    return NRState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
                }
                .compactMap { pubkey in
                    return (
                        pubkey,
                        NRState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL,
                        NRState.shared.loggedInAccount?.followingCache[pubkey]?.anyName ?? "..."
                    )
                }
                .prefix(10))
            
            ConnectionPool.shared.queue.async {
                let statsString = String(format: "%d/%d/%d", stats.connected, stats.messages, stats.errors)
                DispatchQueue.main.async {
                    self.statsString = statsString
                }
            }
        }
    }
}

struct FoundAccountPFPs: View {
    public let foundAccountRows: [(pubkey: String, pfp: URL?, name: String)]
    
    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(foundAccountRows.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: CGFloat(index) * 12)
                    PFP(pubkey: foundAccountRows[index].pubkey, pictureUrl: foundAccountRows[index].pfp, size: 20.0)
                }
                .id(foundAccountRows[index].pubkey)
            }
        }
    }
}

struct RelayStatsDetails: View {
    
    public let stats: RelayConnectionStats
    @State private var errorMessages: [String] = []
    @State private var foundAccountRows: [(pubkey: String, pfp: URL?, name: String)] = []
 
    var body: some View {
        Form {
            if stats.receivedPubkeys.count > 0 {
                Section {
                    ForEach(foundAccountRows.indices, id: \.self) { index in
                        HStack {
                            PFP(pubkey: foundAccountRows[index].pubkey, pictureUrl: foundAccountRows[index].pfp, size: 20.0)
                            Text(foundAccountRows[index].name)
                        }
                    }
                } header: {
                    Text("Accounts found")
                } footer: {
                    Text("Content from these accounts you follow was received from this relay")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    foundAccountRows = stats.receivedPubkeys
                        .filter { pubkey in // We only care about pubkeys we follow
                            return NRState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
                        }
                        .compactMap { pubkey in
                        return (
                            pubkey,
                            NRState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL,
                            NRState.shared.loggedInAccount?.followingCache[pubkey]?.anyName ?? "..."
                        )
                    }
                }
            }

            if errorMessages.count > 0 {
                Section {
                    ForEach(errorMessages.indices, id: \.self) { index in
                        Text(errorMessages[index])
                            .font(.footnote)
                    }
                } header: {
                    Text("Errors")
                } footer: {
                    Text("Last 10 error messages")
                }
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
        let _ = example["wss://nos.lol"]?.lastErrorMessages.insert("Error!!!", at: 0)
        let _ = example["wss://nos.lol"]?.lastErrorMessages.insert("Noooo! Longer longer  Longer longer  Longer longer  Longer longer  Longer longer  Longer longer  Longer longer  Longer longer  Longer longer Long message", at: 0)
        
        let _ = example["wss://relay.nostr.band"]?.messages += 1
        let _ = example["wss://relay.nostr.band"]?.messages += 1
        let _ = example["wss://relay.nostr.band"]?.receivedPubkeys.insert("9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33")
        

        
        RelayStats(stats: example)
    }
}
