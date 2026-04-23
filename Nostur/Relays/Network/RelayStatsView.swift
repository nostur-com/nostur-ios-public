//
//  RelayStats.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/06/2024.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

enum RelayStatsSortMode: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case latency = "Latency"

    var id: String { rawValue }
}

struct RelayStatsView: View {
    
    public let stats: [CanonicalRelayUrl: RelayConnectionStats]
    @State private var showingStats: RelayConnectionStats? = nil
    
    @State private var statsSorted: [RelayConnectionStats] = []
    @State private var sortMode: RelayStatsSortMode = .activity
    @State private var disabledRelayCount: Int = 0
    @State private var collectionPeriodText: String = "min"
    
    var body: some View {
        NXForm {
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
                            showingStats = relayStats        
                        }
                    }
                } header: {
                    HStack {
                        Spacer()
                        Text("(Re)connects/Messages/Errors in last \(collectionPeriodText)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if disabledRelayCount > 0 {
                Section {
                    NavigationLink(destination: DisabledRelaysView()) {
                        Text("\(disabledRelayCount) relays disabled")
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarTitle(String(localized: "Relay stats", comment: "Title for  relay connection statistics sheet"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(RelayStatsSortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            }
                            else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .onAppear {
            refreshSortedStats()
            refreshDisabledRelayCount()
            refreshCollectionPeriodText()
        }
        .onChange(of: sortMode) { _ in
            refreshSortedStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .disabledRelaysDidChange)) { _ in
            refreshDisabledRelayCount()
        }
        .sheet(item: $showingStats, content: { relayConnectionStats in
            NBNavigationStack {
                RelayStatsDetails(stats: relayConnectionStats)
                    .navigationTitle(relayConnectionStats.id)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                showingStats = nil
                            }
                        }
                    }
            }
            
        })
    }

    private func refreshSortedStats() {
        let selectedSortMode = sortMode
        let statsValues = Array(stats.values)
        ConnectionPool.shared.queue.async {
            let sorted: [RelayConnectionStats]
            switch selectedSortMode {
            case .activity:
                sorted = statsValues
                    .sorted(by: { $0.errors < $1.errors })
                    .sorted(by: { $0.receivedPubkeys.count > $1.receivedPubkeys.count })
                    .sorted(by: { $0.connected != 0 && $1.connected == 0 })
            case .latency:
                sorted = statsValues
                    .sorted { left, right in
                        let leftLatency = left.latencyAverages().bestAvailableMs ?? Double.greatestFiniteMagnitude
                        let rightLatency = right.latencyAverages().bestAvailableMs ?? Double.greatestFiniteMagnitude
                        if leftLatency == rightLatency {
                            return left.connected > right.connected
                        }
                        return leftLatency < rightLatency
                    }
            }
            DispatchQueue.main.async {
                self.statsSorted = sorted
            }
        }
    }

    private func refreshDisabledRelayCount() {
        disabledRelayCount = DisabledRelaysStore.count()
    }

    private func refreshCollectionPeriodText() {
        let statsValues = Array(stats.values)
        ConnectionPool.shared.queue.async {
            guard let earliest = statsValues.map(\.firstSeenAt).min() else {
                DispatchQueue.main.async {
                    self.collectionPeriodText = "min"
                }
                return
            }

            let age = Date().timeIntervalSince(earliest)
            let minutes = max(1, Int(age / 60.0))

            let text: String
            if minutes >= 60 {
                let hours = max(1, minutes / 60)
                text = "\(hours) \(hours == 1 ? "hour" : "hours")"
            }
            else {
                text = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
            }

            DispatchQueue.main.async {
                self.collectionPeriodText = text
            }
        }
    }
}

struct RelayStatsRow: View {
    public let stats: RelayConnectionStats
    
    @State private var foundAccountRows: [(pubkey: String, pfp: URL?, name: String)] = []
    @State private var statsString = ""
    @State private var latencyString = "-"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(stats.id.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: ""))
                    .strikethrough(ConnectionPool.shared.penaltybox.contains(stats.id))
                    .lineLimit(1)
                    .layoutPriority(2)

                if stats.lastNoticeMessages.count > 0 {
                    Text("\(stats.lastNoticeMessages.count)")
                        .lineLimit(1)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .background(Capsule().foregroundColor(.orange))
                }

                FoundAccountPFPs(foundAccountRows: foundAccountRows)
                    .layoutPriority(1)

                Spacer()

                Text(statsString)
                    .lineLimit(1)
                    .layoutPriority(3)
            }

            HStack {
                Text(latencyString)
                    .lineLimit(1)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .onAppear {
            foundAccountRows = Array(stats.receivedPubkeys
                .filter { pubkey in // We only care about pubkeys we follow
                    return AccountsState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
                }
                .compactMap { pubkey in
                    return (
                        pubkey,
                        AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL,
                        AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.anyName ?? "..."
                    )
                }
                .prefix(10))
            
            ConnectionPool.shared.queue.async {
                let statsString = String(format: "%d/%d/%d", stats.connected, stats.messages, stats.errors)
                let latency = stats.latencyAverages()
                let latencyString = String(
                    format: "%@/%@/%@",
                    Self.formatLatency(latency.avg5mMs),
                    Self.formatLatency(latency.avg15mMs),
                    Self.formatLatency(latency.avg1hMs)
                )
                DispatchQueue.main.async {
                    self.statsString = statsString
                    self.latencyString = latencyString
                }
            }
        }
    }

    private static func formatLatency(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.0fms", value)
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
    @State private var noticeMessages: [String] = []
    @State private var activeSubscriptions: [String] = []
    @State private var foundAccountRows: [(pubkey: String, pfp: URL?, name: String)] = []
    @State private var latencyAverages: RelayLatencyAverages? = nil
    @State private var neverConnectToRelay: Bool = false
 
    var body: some View {
        NXForm {
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
                            return AccountsState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
                        }
                        .compactMap { pubkey in
                        return (
                            pubkey,
                            AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL,
                            AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.anyName ?? "..."
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
            
            if noticeMessages.count > 0 {
                Section {
                    ForEach(noticeMessages.indices, id: \.self) { index in
                        Text(noticeMessages[index])
                            .font(.footnote)
                    }
                } header: {
                    Text("Notices")
                } footer: {
                    Text("Last 10 notice messages")
                }
            }

            Section {
                if activeSubscriptions.isEmpty {
                    Text("None")
                        .foregroundColor(.secondary)
                }
                else {
                    ForEach(activeSubscriptions, id: \.self) { subscriptionId in
                        Text(subscriptionId)
                            .font(.footnote)
                    }
                }
            } header: {
                Text("Active subscriptions (\(activeSubscriptions.count))")
            }
            
            if let latencyAverages {
                Section {
                    HStack {
                        Text("Last 5 minutes")
                        Spacer()
                        Text(Self.formatLatency(latencyAverages.avg5mMs))
                    }
                    HStack {
                        Text("Last 15 minutes")
                        Spacer()
                        Text(Self.formatLatency(latencyAverages.avg15mMs))
                    }
                    HStack {
                        Text("Last 1 hour")
                        Spacer()
                        Text(Self.formatLatency(latencyAverages.avg1hMs))
                    }
                } header: {
                    Text("REQ response latency")
                } footer: {
                    Text("Samples (5m/15m/1h): \(latencyAverages.samples5m)/\(latencyAverages.samples15m)/\(latencyAverages.samples1h)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if shouldShowNeverConnectToggle {
                Section {
                    Toggle("Never connect to this relay", isOn: Binding(
                        get: { neverConnectToRelay },
                        set: { newValue in
                            neverConnectToRelay = newValue
                            DisabledRelaysStore.setDisabled(stats.id, isDisabled: newValue)
                            if newValue {
                                ConnectionPool.shared.disconnectRelay(stats.id)
                            }
                        }
                    ))
                }
            }
        }
        .onAppear {
            neverConnectToRelay = DisabledRelaysStore.isDisabled(stats.id)
            ConnectionPool.shared.queue.async {
                let lastErrorMessages = stats.lastErrorMessages
                let lastNoticeMessages = stats.lastNoticeMessages
                let latencyAverages = stats.latencyAverages()
                let relayId = normalizeRelayUrl(stats.id)
                let activeSubscriptions = ConnectionPool.shared.connections[relayId]
                    .map { Array($0.nreqSubscriptions).sorted() } ?? []
                DispatchQueue.main.async {
                    errorMessages = lastErrorMessages
                    noticeMessages = lastNoticeMessages
                    self.latencyAverages = latencyAverages
                    self.activeSubscriptions = activeSubscriptions
                }
            }
        }
    }

    private var cannotEnableNeverConnect: Bool {
        let relayId = normalizeRelayUrl(stats.id)
        let inConnections = ConnectionPool.shared.connections[relayId] != nil
        let inCloudRelays = CloudRelay.fetchAll().contains(where: { relay in
            guard let relayUrl = relay.url_ else { return false }
            return normalizeRelayUrl(relayUrl) == relayId
        })
        return inConnections || inCloudRelays
    }

    private var shouldShowNeverConnectToggle: Bool {
        neverConnectToRelay || !cannotEnableNeverConnect
    }

    private static func formatLatency(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f ms", value)
    }
}

private struct DisabledRelaysView: View {
    @State private var disabledRelays: [CanonicalRelayUrl] = []

    var body: some View {
        List {
            ForEach(disabledRelays, id: \.self) { relay in
                Text(relay)
            }
            .onDelete(perform: removeRelays)
        }
        .navigationTitle("Disabled relays")
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .disabledRelaysDidChange)) { _ in
            refresh()
        }
    }

    private func refresh() {
        disabledRelays = DisabledRelaysStore.all()
    }

    private func removeRelays(at offsets: IndexSet) {
        for index in offsets {
            DisabledRelaysStore.setDisabled(disabledRelays[index], isDisabled: false)
        }
    }
}

#Preview {
    NBNavigationStack {
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
        

        
        RelayStatsView(stats: example)
    }
}
