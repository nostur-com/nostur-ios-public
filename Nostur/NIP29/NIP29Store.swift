//
//  NIP29Store.swift
//  Nostur
//

import Combine
import Foundation

@MainActor
final class NIP29Store: ObservableObject {
    private struct RecentRelayEvent {
        let id: String
        let pubkey: String
    }

    @Published private(set) var groups: [NIP29GroupAddress: NIP29GroupSnapshot] = [:]

    private var seenEventIds: [NIP29GroupAddress: Set<String>] = [:]
    private var recentRelayEvents: [NIP29GroupAddress: [RecentRelayEvent]] = [:]
    private let maximumTimelineCount: Int

    init(maximumTimelineCount: Int = 1_000) {
        self.maximumTimelineCount = maximumTimelineCount
    }

    func snapshot(for address: NIP29GroupAddress) -> NIP29GroupSnapshot {
        groups[address] ?? NIP29GroupSnapshot(id: address)
    }

    func prepare(_ address: NIP29GroupAddress) {
        guard groups[address] == nil else { return }
        groups[address] = NIP29GroupSnapshot(id: address)
    }

    func setConnectionState(_ state: NIP29ConnectionState, for addresses: Set<NIP29GroupAddress>) {
        mutate(addresses) { snapshot in
            snapshot.connectionState = state
            if case .failed(let message) = state {
                snapshot.lastError = message
            }
        }
    }

    func markEOSE(for address: NIP29GroupAddress) {
        mutate(address) { $0.hasLoadedInitialPage = true }
    }

    func setError(_ message: String?, for address: NIP29GroupAddress) {
        mutate(address) { $0.lastError = message }
    }

    func ingest(_ event: NEvent, from address: NIP29GroupAddress, accountPubkey: String) {
        let kind = event.kind.id
        let belongsToGroup = NIP29Kind.relayGeneratedKinds.contains(kind)
            ? NIP29Protocol.metadataGroupId(in: event) == address.groupId
            : NIP29Protocol.groupId(in: event) == address.groupId
        guard belongsToGroup else { return }

        var ids = seenEventIds[address, default: []]
        guard ids.insert(event.id).inserted else { return }
        seenEventIds[address] = ids

        if !NIP29Kind.relayGeneratedKinds.contains(kind) {
            var recent = recentRelayEvents[address, default: []]
            recent.append(RecentRelayEvent(id: event.id, pubkey: event.publicKey))
            if recent.count > 50 { recent.removeFirst(recent.count - 50) }
            recentRelayEvents[address] = recent
        }

        mutate(address) { snapshot in
            switch kind {
            case NIP29Kind.groupMetadata:
                snapshot.metadata = NIP29GroupMetadata(event: event)
            case NIP29Kind.groupAdmins:
                snapshot.admins = event.tags.compactMap(NIP29Protocol.member(from:)).sorted { $0.pubkey < $1.pubkey }
            case NIP29Kind.groupMembers:
                snapshot.members = event.tags.compactMap(NIP29Protocol.member(from:)).sorted { $0.pubkey < $1.pubkey }
                snapshot.isMember = snapshot.members.contains { $0.pubkey == accountPubkey }
            case NIP29Kind.putUser:
                applyMembershipEvent(event, isAdding: true, accountPubkey: accountPubkey, snapshot: &snapshot)
            case NIP29Kind.removeUser:
                applyMembershipEvent(event, isAdding: false, accountPubkey: accountPubkey, snapshot: &snapshot)
            default:
                guard !NIP29Kind.managementRange.contains(kind) else { return }
                insertTimelineEvent(NIP29EventSnapshot(event: event), into: &snapshot.timeline)
            }
        }
    }

    func previousEventIds(for address: NIP29GroupAddress, excludingPubkey: String) -> [String] {
        Array(
            recentRelayEvents[address, default: []]
                .filter { $0.pubkey != excludingPubkey }
                .map(\.id)
                .suffix(3)
        )
    }

    private func applyMembershipEvent(
        _ event: NEvent,
        isAdding: Bool,
        accountPubkey: String,
        snapshot: inout NIP29GroupSnapshot
    ) {
        guard let member = event.tags.lazy.compactMap(NIP29Protocol.member(from:)).first else { return }
        snapshot.members.removeAll { $0.pubkey == member.pubkey }
        if isAdding { snapshot.members.append(member) }
        snapshot.members.sort { $0.pubkey < $1.pubkey }
        if member.pubkey == accountPubkey { snapshot.isMember = isAdding }
    }

    private func insertTimelineEvent(_ event: NIP29EventSnapshot, into timeline: inout [NIP29EventSnapshot]) {
        let insertionIndex = timeline.partitioningIndex {
            ($0.createdAt, $0.id) >= (event.createdAt, event.id)
        }
        timeline.insert(event, at: insertionIndex)
        if timeline.count > maximumTimelineCount {
            timeline.removeFirst(timeline.count - maximumTimelineCount)
        }
    }

    private func mutate(_ address: NIP29GroupAddress, _ body: (inout NIP29GroupSnapshot) -> Void) {
        var snapshot = groups[address] ?? NIP29GroupSnapshot(id: address)
        let oldSnapshot = snapshot
        body(&snapshot)
        guard snapshot != oldSnapshot else { return }
        groups[address] = snapshot
    }

    private func mutate(_ addresses: Set<NIP29GroupAddress>, _ body: (inout NIP29GroupSnapshot) -> Void) {
        guard !addresses.isEmpty else { return }
        var updatedGroups = groups
        var didChange = false
        for address in addresses {
            var snapshot = updatedGroups[address] ?? NIP29GroupSnapshot(id: address)
            let oldSnapshot = snapshot
            body(&snapshot)
            if snapshot != oldSnapshot {
                updatedGroups[address] = snapshot
                didChange = true
            }
        }
        if didChange { groups = updatedGroups }
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let distance = self.distance(from: low, to: high)
            let middle = index(low, offsetBy: distance / 2)
            if predicate(self[middle]) {
                high = middle
            } else {
                low = index(after: middle)
            }
        }
        return low
    }
}
