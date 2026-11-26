import SwiftUI
import CoreData
import NostrEssentials

struct LegacyRelayConfiguration: Identifiable, Equatable {
    struct Relay: Identifiable, Equatable {
        let url: String
        var read: Bool
        var write: Bool

        var id: String { url }
    }

    let content: String
    let relays: [Relay]
    var id: String { content }

    init?(content: String) {
        guard let configuration = try? JSONDecoder().decode(Kind3Relays.self, from: Data(content.utf8)) else { return nil }
        self.relays = configuration.relays.filter { Self.isRelayURL($0.url) }
            .map { Relay(url: $0.url, read: $0.readWrite.read ?? false, write: $0.readWrite.write ?? false) }
            .sorted { $0.url < $1.url }
        guard !relays.isEmpty else { return nil }
        self.content = content
    }

    static func isRelayURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    func replacementEvent(for latest: NEvent, editing editedRelays: [Relay], now: Date = .now) throws -> NEvent {
        guard latest.kind == .contactList, latest.content == content else { throw EditError.configurationChanged }
        let timestamp = max(Int(now.timeIntervalSince1970), latest.createdAt.timestamp + 1)
        return NEvent(publicKey: latest.publicKey, createdAt: NTimestamp(timestamp: timestamp),
                      content: try content(updating: editedRelays), kind: .contactList, tags: latest.tags)
    }

    private func content(updating editedRelays: [Relay]) throws -> String {
        guard var entries = try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: [String: Any]] else {
            throw CocoaError(.coderInvalidValue)
        }
        let originals = Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) })
        let editedURLs = Set(editedRelays.map(\.url))
        for relay in relays where !editedURLs.contains(relay.url) {
            entries.removeValue(forKey: relay.url)
        }
        for relay in editedRelays where originals[relay.url] != relay {
            if originals[relay.url]?.read != relay.read {
                entries[relay.url, default: [:]]["read"] = relay.read
            }
            if originals[relay.url]?.write != relay.write {
                entries[relay.url, default: [:]]["write"] = relay.write
            }
        }
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}

private enum EditError: LocalizedError {
    case configurationChanged
    case followUpdatePending

    var errorDescription: String? {
        switch self {
        case .configurationChanged:
            String(localized: "Your follow list changed while editing. Reopen Announced Relays and try again.")
        case .followUpdatePending:
            String(localized: "A follow list update is waiting to publish. Try again in a few seconds.")
        }
    }
}

struct LegacyRelayEditor: View {
    @Environment(\.dismiss) private var dismiss
    let account: CloudAccount
    let configuration: LegacyRelayConfiguration
    let onPublished: (LegacyRelayConfiguration?) -> Void

    @State private var relays: [LegacyRelayConfiguration.Relay]
    @State private var newURL = ""
    @State private var publishing = false
    @State private var errorMessage: String?

    init(account: CloudAccount, configuration: LegacyRelayConfiguration, onPublished: @escaping (LegacyRelayConfiguration?) -> Void) {
        self.account = account
        self.configuration = configuration
        self.onPublished = onPublished
        _relays = State(initialValue: configuration.relays)
    }

    var body: some View {
        NXForm {
            ForEach($relays) { $relay in
                let url = relay.url
                LegacyRelayRow(relay: $relay) {
                    relays.removeAll { $0.url == url }
                }
            }
            .disabled(publishing)

            Section {
                TextField("Relay URL", text: $newURL, prompt: Text("wss://relay.example.com"))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Add relay") {
                    relays.append(.init(url: relayURL, read: true, write: true))
                    newURL = ""
                }
                .disabled(!canAddRelay)
            }
            .disabled(publishing)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Old relays")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(publishing)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                    .disabled(publishing)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Publish", systemImage: "checkmark") {
                    publishing = true
                    errorMessage = nil
                    Task { await publish() }
                }
                .disabled(publishing || relays == configuration.relays)
            }
        }
    }

    private var relayURL: String {
        newURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddRelay: Bool {
        LegacyRelayConfiguration.isRelayURL(relayURL) && !relays.contains {
            normalizeRelayUrl($0.url) == normalizeRelayUrl(relayURL)
        }
    }

    private func publish() async {
        defer { publishing = false }
        let pubkey = account.publicKey
        let context = bg()
        do {
            try checkForPendingFollowUpdate(pubkey: pubkey)
            let latest = await context.perform {
                Event.fetchReplacableEvent(3, pubkey: pubkey, context: context)?.toNEvent()
            }
            guard let latest else { throw EditError.configurationChanged }
            var event = try configuration.replacementEvent(for: latest, editing: relays)
            let signed = try await signPreparedEvent(event.withId(), account: account)

            try checkForPendingFollowUpdate(pubkey: pubkey)
            try await context.perform {
                guard Event.fetchReplacableEvent(3, pubkey: pubkey, context: context)?.id == latest.id else {
                    throw EditError.configurationChanged
                }
                _ = Event.saveEvent(event: signed, context: context)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            Unpublisher.shared.publishNow(signed)
            onPublished(LegacyRelayConfiguration(content: signed.content))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkForPendingFollowUpdate(pubkey: String) throws {
        if Unpublisher.shared.queue.contains(where: { $0.type == .contactList && $0.nEvent.publicKey == pubkey }) {
            throw EditError.followUpdatePending
        }
    }

}

private struct LegacyRelayRow: View {
    @Binding var relay: LegacyRelayConfiguration.Relay
    let onRemove: () -> Void

    var body: some View {
        DisclosureGroup {
            Toggle("Read", isOn: $relay.read)
            Toggle("Write", isOn: $relay.write)
            Button("Remove relay", role: .destructive, action: onRemove)
        } label: {
            Text(relay.url)
        }
    }
}
