import SwiftUI
import NavigationBackport
import NostrEssentials

struct ScannedProfile: Hashable {
    let pubkey: String
    let relays: [String]

    static func parse(_ value: String) -> Self? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("nostr:") { value = String(value.dropFirst(6)) }
        guard value.count <= 8192 else { return nil }
        if value.lowercased().hasPrefix("npub1"), let key = Keys.hex(npub: value.lowercased()), key.count == 64 {
            return Self(pubkey: key, relays: [])
        }
        guard value.lowercased().hasPrefix("nprofile1"),
              let (prefix, data) = try? Bech32.decode(other: value.lowercased()), prefix == "nprofile" else { return nil }
        var pubkey: String?
        var relays: [String] = []
        var offset = 0
        while offset < data.count {
            guard offset + 2 <= data.count else { return nil }
            let type = data[offset]
            let length = Int(data[offset + 1])
            offset += 2
            guard offset + length <= data.count else { return nil }
            let field = data.subdata(in: offset..<(offset + length))
            offset += length
            if type == 0 {
                guard length == 32, pubkey == nil else { return nil }
                pubkey = field.hexEncodedString()
            } else if type == 1 {
                guard let relay = String(data: field, encoding: .utf8) else { return nil }
                relays.append(relay)
            }
        }
        guard let pubkey else { return nil }
        return Self(pubkey: pubkey, relays: relayHints(relays))
    }

    static func relayHints(_ values: [String], limit: Int = 3) -> [String] {
        var seen = Set<String>()
        return Array(values.compactMap { value -> String? in
            guard value.utf8.count <= 255, let url = URLComponents(string: value),
                  ["wss", "ws"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.fragment == nil else { return nil }
            let normalized = normalizeRelayUrl(value)
            return seen.insert(normalized).inserted ? normalized : nil
        }.prefix(limit))
    }
}

struct ProfileShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pubkey: String
    let name: String
    let pictureUrl: URL?
    @State private var identifier: String?
    @State private var format: ShareFormat = .nprofile
    @State private var copiedValue: String?
    @State private var showSystemShare = false
    @State private var showFormatInfo = false
    @State private var verifyingRelays = true
    @State private var verificationAttempt = 0

    private var npub: String { (try? NostrEssentials.ShareableIdentifier("npub", pubkey: pubkey))?.identifier ?? "" }

    private var sharedRelays: [String] {
        identifier.flatMap(ScannedProfile.parse)?.relays ?? []
    }

    private enum ShareFormat: Hashable {
        case npub, nprofile
    }

    // The QR, visible text, clipboard, and system share always use this exact payload.
    private var shareValue: String? {
        switch format {
        case .npub: return "nostr:" + npub
        case .nprofile: return verifyingRelays ? nil : identifier.map { "nostr:" + $0 }
        }
    }

    var body: some View {
        NBNavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PFP(pubkey: pubkey, pictureUrl: pictureUrl, size: 80)
                    Text(name).font(.title2.bold()).multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        // Balance the info button so the picker itself stays centered on the QR.
                        Color.clear
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                        Picker("Share as", selection: $format) {
                            Text("npub").tag(ShareFormat.npub)
                            Text("nprofile").tag(ShareFormat.nprofile)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Share as")
                        .frame(maxWidth: 220)
                        Button { showFormatInfo = true } label: {
                            Label("About sharing formats", systemImage: "info.circle")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(maxWidth: 324)
                    if let shareValue, let qr = generateQRCode(from: shareValue) {
                        qr.resizable().interpolation(.none).scaledToFit()
                            .padding(20).background(.white)
                            .frame(maxWidth: 300)
                            .accessibilityLabel("Profile QR code")
                    } else {
                        ProgressView("Checking profile on relays…").frame(height: 260)
                    }
                    if let shareValue {
                        HStack {
                            Text(shareValue)
                                .font(.footnote.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = shareValue
                                copiedValue = shareValue
                            } label: {
                                Label(copiedValue == shareValue ? "Copied" : "Copy", systemImage: copiedValue == shareValue ? "checkmark" : "doc.on.doc")
                                    .frame(width: 44, height: 44)
                            }
                            .labelStyle(.iconOnly)
                        }
                        if format == .nprofile {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Included relays")
                                    .fontWeight(.medium)
                                if sharedRelays.isEmpty {
                                    Text("Couldn't confirm this profile on any relay. You can share the npub or try again.")
                                    Button("Try again") { verificationAttempt += 1 }
                                } else {
                                    Text(sharedRelays.joined(separator: "\n"))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity)
            }
            .navigationTitle("Share profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSystemShare = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(shareValue == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showSystemShare) {
                if let shareValue {
                    ActivityView(activityItems: [shareValue])
                }
            }
            .alert("Sharing formats", isPresented: $showFormatInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("npub shares just your Nostr ID.\n\nnprofile shares your Nostr ID plus up to two relays where your profile can be found, when available. This helps other apps find you.")
            }
            .task(id: verificationAttempt) { await prepare() }
            .task(id: shareValue) { copiedValue = nil }
        }.nbUseNavigationStack(.never)
    }

    @MainActor
    private func prepare() async {
        verifyingRelays = true
        identifier = nil
        let isOwn = AccountsState.shared.activeAccountPublicKey == pubkey
        let configured = CloudRelay.fetchAll(context: DataProvider.shared().viewContext)
        let excluded = Set(configured.filter { $0.auth || $0.excludedPubkeys.contains(pubkey) }.compactMap { $0.url_ }.map(normalizeRelayUrl))
        let fallback = isOwn ? configured.filter {
            $0.write && !$0.auth && !$0.excludedPubkeys.contains(pubkey)
        }.compactMap { $0.url_ } : []
        let snapshot = await ProfileSharingSnapshot.load(pubkey: pubkey)
        guard !Task.isCancelled else { return }
        if isOwn {
            // Republish the existing signed metadata and relay list through the normal write flow.
            for json in snapshot.events {
                guard let event = NEvent.fromString(json) else { continue }
                ConnectionPool.shared.sendMessage(NosturClientMessage(
                    clientMessage: NostrEssentials.ClientMessage(type: .EVENT, event: event.toNostrEssentialsEvent()),
                    relayType: .WRITE, nEvent: event), accountPubkey: pubkey)
            }
        }
        let candidates = ScannedProfile.relayHints(snapshot.advertised + fallback.sorted() + snapshot.received.sorted(), limit: 6)
            .filter { !excluded.contains($0) && !DisabledRelaysStore.isDisabled($0) }
        let confirmed: [String]
        if vpnGuardOK() {
            let profilePubkey = pubkey
            confirmed = await ProfileRelayVerification.confirmedRelays(candidates) { relay in
                guard !Task.isCancelled, let url = URL(string: relay) else { return false }
                let verifier = ProfileRelayVerifier(transport: ProfileRelaySocket(url: url))
                return await verifier.verify(pubkey: profilePubkey, minimumCreatedAt: snapshot.minimumCreatedAt,
                                             publishing: isOwn ? snapshot.events : [])
            }
        } else { confirmed = [] }
        guard !Task.isCancelled else { return }
        identifier = (try? NostrEssentials.ShareableIdentifier("nprofile", pubkey: pubkey, relays: confirmed))?.identifier
        verifyingRelays = false
    }
}

// Navigation stays responsive while profile lookup runs; relay hints are never saved as settings.
struct ScannedProfileView: View {
    let profile: ScannedProfile
    @State private var contact: NRContact?
    @State private var timedOut = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let contact { ProfileView(nrContact: contact) }
            else if timedOut {
                VStack(spacing: 16) {
                    Text("Couldn't load this profile. Check your connection and try again.")
                    Button("Try again") { attempt += 1 }
                }.padding()
            } else { ProgressView("Loading profile…") }
        }
        .task(id: attempt) {
            timedOut = false
            let subscription = "SCAN-" + UUID().uuidString
            let message = RM.getUserMetadata(pubkey: profile.pubkey, subscriptionId: subscription)
            req(message, relayType: .READ)
            req(message, relayType: .SEARCH_ONLY)
            for relay in profile.relays {
                ConnectionPool.shared.sendEphemeralMessage(message, relay: relay)
            }
            defer {
                let close = "[\"CLOSE\",\"\(subscription)\"]"
                req(close, relayType: .READ)
                req(close, relayType: .SEARCH_ONLY)
                for relay in profile.relays { ConnectionPool.shared.sendEphemeralMessage(close, relay: relay) }
            }
            let ctx = bg()
            for _ in 0..<24 {
                guard !Task.isCancelled else { return }
                if let result = await ctx.perform({ Contact.fetchByPubkey(profile.pubkey, context: ctx).flatMap { NRContact.fetch(profile.pubkey, contact: $0) } }) {
                    contact = result
                    return
                }
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
            timedOut = true
        }
    }
}
