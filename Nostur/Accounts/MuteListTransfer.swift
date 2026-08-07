//
//  MuteListTransfer.swift
//  Nostur
//
//  Manual NIP-51 mute-list import and export.
//

import SwiftUI
import NostrEssentials

enum NIP51MuteListPrivacy: String, CaseIterable, Identifiable {
    case publicList = "Public"
    case privateList = "Private"

    var id: Self { self }
}

enum NIP51MuteListPrivateContentStatus: Equatable {
    case absent
    case decoded(Int)
    case keyUnavailable
    case decryptionFailed
}

struct NIP51DecodedMuteList: Equatable {
    let pubkeys: Set<String>
    let publicCount: Int
    let privateContentStatus: NIP51MuteListPrivateContentStatus
    let snapshot: NIP51MuteListSnapshot
}

struct NIP51MuteListSnapshot: Equatable {
    let publicTags: [[String]]
    let encryptedContent: String
    let privateTags: [[String]]?
}

enum NIP51MuteListCodecError: LocalizedError {
    case invalidEvent
    case privateKeyUnavailable
    case encryptionFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidEvent:
            return "The saved list could not be read."
        case .privateKeyUnavailable:
            return "This account cannot create a private list on this device."
        case .encryptionFailed:
            return "The private list could not be protected."
        case .encodingFailed:
            return "The list could not be prepared."
        }
    }
}

struct NIP51MuteListCodec {
    static let kind = 10000

    static func decode(_ event: NEvent, privateKey: String?) throws -> NIP51DecodedMuteList {
        guard event.kind.id == kind else { throw NIP51MuteListCodecError.invalidEvent }

        let publicPubkeys = Set(event.tags.compactMap { tag -> String? in
            guard tag.type == "p", isValidPubkey(tag.pubkey) else { return nil }
            return tag.pubkey
        })

        guard !event.content.isEmpty else {
            return NIP51DecodedMuteList(
                pubkeys: publicPubkeys,
                publicCount: publicPubkeys.count,
                privateContentStatus: .absent,
                snapshot: NIP51MuteListSnapshot(
                    publicTags: event.tags.map(\.tag),
                    encryptedContent: "",
                    privateTags: []
                )
            )
        }

        guard let privateKey else {
            return NIP51DecodedMuteList(
                pubkeys: publicPubkeys,
                publicCount: publicPubkeys.count,
                privateContentStatus: .keyUnavailable,
                snapshot: NIP51MuteListSnapshot(
                    publicTags: event.tags.map(\.tag),
                    encryptedContent: event.content,
                    privateTags: nil
                )
            )
        }

        // NIP-51 currently uses NIP-44. Try the legacy NIP-04 format as a
        // fallback because older mute lists can still exist on relays.
        guard let decrypted = Keys.decryptDirectMessageContent44(
            withPrivateKey: privateKey,
            pubkey: event.publicKey,
            content: event.content
        ) ?? Keys.decryptDirectMessageContent(
            withPrivateKey: privateKey,
            pubkey: event.publicKey,
            content: event.content
        ) else {
            return NIP51DecodedMuteList(
                pubkeys: publicPubkeys,
                publicCount: publicPubkeys.count,
                privateContentStatus: .decryptionFailed,
                snapshot: NIP51MuteListSnapshot(
                    publicTags: event.tags.map(\.tag),
                    encryptedContent: event.content,
                    privateTags: nil
                )
            )
        }

        guard let data = decrypted.data(using: .utf8),
              let privateTags = try? JSONDecoder().decode([[String]].self, from: data) else {
            return NIP51DecodedMuteList(
                pubkeys: publicPubkeys,
                publicCount: publicPubkeys.count,
                privateContentStatus: .decryptionFailed,
                snapshot: NIP51MuteListSnapshot(
                    publicTags: event.tags.map(\.tag),
                    encryptedContent: event.content,
                    privateTags: nil
                )
            )
        }

        let privatePubkeys = Set(privateTags.compactMap { tag -> String? in
            guard tag.count >= 2, tag[0] == "p", isValidPubkey(tag[1]) else { return nil }
            return tag[1]
        })

        return NIP51DecodedMuteList(
            pubkeys: publicPubkeys.union(privatePubkeys),
            publicCount: publicPubkeys.count,
            privateContentStatus: .decoded(privatePubkeys.count),
            snapshot: NIP51MuteListSnapshot(
                publicTags: event.tags.map(\.tag),
                encryptedContent: event.content,
                privateTags: privateTags
            )
        )
    }

    static func makeUnsignedEvent(
        pubkeys: Set<String>,
        authorPubkey: String,
        privacy: NIP51MuteListPrivacy,
        privateKey: String?
    ) throws -> NEvent {
        try makeMergedUnsignedEvent(
            localPubkeys: pubkeys,
            authorPubkey: authorPubkey,
            privacy: privacy,
            privateKey: privateKey,
            existing: nil
        )
    }

    static func makeMergedUnsignedEvent(
        localPubkeys: Set<String>,
        authorPubkey: String,
        privacy: NIP51MuteListPrivacy,
        privateKey: String?,
        existing: NIP51MuteListSnapshot?
    ) throws -> NEvent {
        var event = NEvent(content: "")
        event.kind = .custom(kind)
        event.publicKey = authorPubkey
        event.createdAt = NTimestamp(date: .now)

        var publicTags = existing?.publicTags ?? []
        let privateTags = existing?.privateTags
        let existingPublicPubkeys = Set(publicTags.compactMap { tag -> String? in
            guard tag.count >= 2, tag[0] == "p", isValidPubkey(tag[1]) else { return nil }
            return tag[1]
        })
        let existingPrivatePubkeys = Set((privateTags ?? []).compactMap { tag -> String? in
            guard tag.count >= 2, tag[0] == "p", isValidPubkey(tag[1]) else { return nil }
            return tag[1]
        })
        let additions = Set(localPubkeys.filter(isValidPubkey))
            .subtracting(existingPublicPubkeys)
            .subtracting(existingPrivatePubkeys)
            .sorted()

        switch privacy {
        case .publicList:
            publicTags.append(contentsOf: additions.map { ["p", $0] })
            event.tags = publicTags.map(NostrTag.init)
            // Existing private entries are deliberately kept byte-for-byte.
            // This also makes public export safe when this device cannot read them.
            event.content = existing?.encryptedContent ?? ""

        case .privateList:
            guard let privateKey else { throw NIP51MuteListCodecError.privateKeyUnavailable }
            if let existing, !existing.encryptedContent.isEmpty, privateTags == nil {
                throw NIP51MuteListCodecError.encryptionFailed
            }
            let combinedPrivateTags = (privateTags ?? []) + additions.map { ["p", $0] }
            guard let data = try? JSONEncoder().encode(combinedPrivateTags),
                  let json = String(data: data, encoding: .utf8) else {
                throw NIP51MuteListCodecError.encodingFailed
            }
            guard let encrypted = Keys.encryptDirectMessageContent44(
                withPrivatekey: privateKey,
                pubkey: authorPubkey,
                content: json
            ) else {
                throw NIP51MuteListCodecError.encryptionFailed
            }
            event.tags = publicTags.map(NostrTag.init)
            event.content = encrypted
        }

        return event
    }
}

struct MuteListImportPreview: Equatable {
    let sourcePubkeys: Set<String>
    let newPubkeys: Set<String>
    let alreadyBlockedCount: Int
    let publicCount: Int
    let privateContentStatus: NIP51MuteListPrivateContentStatus
}

struct MuteListImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @StateObject private var fetcher = FetchVM<MuteListImportPreview>(timeout: 8, backlogDebugName: "MuteListImport")

    @State private var selectedAccount: CloudAccount?
    @State private var importedCount: Int?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Choose account") {
                AccountPicker(selectedAccount: $selectedAccount, label: "Account", required: true)
                    .disabled(isLoading)

                if case .initializing = fetcher.state {
                    Button("Search on relays", systemImage: "arrow.down.doc") {
                        fetch()
                    }
                    .disabled(selectedAccount == nil)
                }
            }

            switch fetcher.state {
            case .initializing:
                Section {
                    Text("Nostur will look for blocks this account saved using other apps. Nothing changes until you confirm.")
                        .foregroundStyle(.secondary)
                }

            case .loading, .altLoading:
                Section {
                    HStack {
                        ProgressView()
                        Text("Looking for saved blocks…")
                    }
                }

            case .ready(let preview):
                previewSection(preview)

            case .timeout:
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.title)
                        Text("No saved blocks found")
                            .font(.headline)
                        Text("This account does not appear to have a saved block list yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    Button("Try again") { fetcher.fetch() }
                }

            case .error(let message):
                Section {
                    Text(message).foregroundStyle(.red)
                    Button("Try again") { fetcher.fetch() }
                }
            }
        }
        .navigationTitle("Import from relays")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selectedAccount = AccountsState.shared.accounts.first {
                $0.publicKey == AccountsState.shared.activeAccountPublicKey
            } ?? AccountsState.shared.accounts.first
        }
        .onChange(of: selectedAccount?.publicKey) { _ in
            guard !isLoading else { return }
            fetcher.state = .initializing
            importedCount = nil
        }
    }

    private var isLoading: Bool {
        switch fetcher.state {
        case .loading, .altLoading:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func previewSection(_ preview: MuteListImportPreview) -> some View {
        Section("Preview") {
            MuteListCountRow("Found", count: preview.sourcePubkeys.count)
            MuteListCountRow("Already in Nostur", count: preview.alreadyBlockedCount)
            MuteListCountRow("New blocks", count: preview.newPubkeys.count)

            switch preview.privateContentStatus {
            case .absent:
                if preview.publicCount > 0 {
                    Label("These blocks are visible to everyone.", systemImage: "globe")
                        .foregroundStyle(.secondary)
                }
            case .decoded(let count):
                Label("Read \(count) private blocks.", systemImage: "lock.open")
                    .foregroundStyle(.secondary)
            case .keyUnavailable:
                Label("Some private blocks could not be read by this device.", systemImage: "lock")
                    .foregroundStyle(.orange)
            case .decryptionFailed:
                Label("Some private blocks could not be read.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }

        Section {
            if let importedCount {
                Label("Added \(importedCount) blocks", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            else if preview.newPubkeys.isEmpty {
                Label("Nothing new to import", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            else {
                Button("Add \(preview.newPubkeys.count) blocks to Nostur", systemImage: "plus.circle") {
                    importMutes(preview.newPubkeys)
                }
                .buttonStyleGlassProminent()
            }

            Text("Your existing Nostur blocks will not be removed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func fetch() {
        guard let selectedAccount else { return }

        let pubkey = selectedAccount.publicKey
        let privateKey = selectedAccount.isNC ? nil : selectedAccount.privateKey
        let localPubkeys = CloudBlocked.blockedPubkeys()

        fetcher.setFetchParams((
            prio: false,
            req: { taskId in
                req(RM.getUserProfileKinds(pubkey: pubkey, subscriptionId: taskId, kinds: [NIP51MuteListCodec.kind]))
            },
            onComplete: { [weak fetcher] _, _ in
                bg().perform {
                    guard let fetcher,
                          let event = Event.fetchReplacableEvent(Int64(NIP51MuteListCodec.kind), pubkey: pubkey, context: bg()) else {
                        fetcher?.timeout()
                        return
                    }

                    do {
                        let decoded = try NIP51MuteListCodec.decode(event.toNEvent(), privateKey: privateKey)
                        let additions = decoded.pubkeys.subtracting(localPubkeys)
                        fetcher.ready(MuteListImportPreview(
                            sourcePubkeys: decoded.pubkeys,
                            newPubkeys: additions,
                            alreadyBlockedCount: decoded.pubkeys.intersection(localPubkeys).count,
                            publicCount: decoded.publicCount,
                            privateContentStatus: decoded.privateContentStatus
                        ))
                    }
                    catch {
                        fetcher.error(error.localizedDescription)
                    }
                }
            },
            altReq: nil
        ))
        fetcher.fetch()
    }

    @MainActor
    private func importMutes(_ pubkeys: Set<String>) {
        let existing = CloudBlocked.blockedPubkeys()
        let additions = pubkeys.subtracting(existing)

        additions.forEach { CloudBlocked.addBlock(pubkey: $0) }
        AppState.shared.bgAppState.blockedPubkeys.formUnion(additions)
        DataProvider.shared().saveToDiskNow(.viewContext)
        sendNotification(.blockListUpdated, AppState.shared.bgAppState.blockedPubkeys)
        importedCount = additions.count
    }
}

struct MuteListExportPreview: Equatable {
    enum ExistingListStatus: Equatable {
        case found
        case notFound
        case notConfirmed
    }

    let accountPubkey: String
    let existingPubkeys: Set<String>
    let combinedPubkeys: Set<String>
    let existingListStatus: ExistingListStatus
    let privateContentStatus: NIP51MuteListPrivateContentStatus
    let existingSnapshot: NIP51MuteListSnapshot?

    var existingListFound: Bool { existingListStatus == .found }

    func canSafelyReplaceExistingList(privacy: NIP51MuteListPrivacy) -> Bool {
        if privacy == .publicList { return true }

        switch privateContentStatus {
        case .absent, .decoded:
            return true
        case .keyUnavailable, .decryptionFailed:
            return false
        }
    }
}

struct MuteListExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.contact.rawValue)
    ) private var blockedContacts: FetchedResults<CloudBlocked>
    @StateObject private var fetcher = FetchVM<MuteListExportPreview>(timeout: 8, backlogDebugName: "MuteListExport")

    @State private var selectedAccount: CloudAccount?
    @State private var privacy: NIP51MuteListPrivacy = .privateList
    @State private var temporaryPubkeys: Set<String> = []
    @State private var statusMessage: String?
    @State private var isPublishing = false
    @State private var didPublish = false
    @State private var showPublishWithoutCheckConfirmation = false
    @State private var didLoad = false

    private var exportPubkeys: Set<String> {
        Set(blockedContacts.compactMap(\.pubkey_)).subtracting(temporaryPubkeys)
    }

    private var checkedPreview: MuteListExportPreview? {
        guard case .ready(let preview) = fetcher.state,
              preview.accountPubkey == selectedAccount?.publicKey else { return nil }
        return preview
    }

    private var isChecking: Bool {
        switch fetcher.state {
        case .loading, .altLoading:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Form {
            Section("Choose account") {
                FullAccountPicker(selectedAccount: $selectedAccount, label: "Account", required: true)
                    .disabled(isChecking)
            }

            Section("Who can see the blocks?") {
                Picker("Visibility", selection: $privacy) {
                    Text("Only me").tag(NIP51MuteListPrivacy.privateList)
                    Text("Everyone").tag(NIP51MuteListPrivacy.publicList)
                }
                .pickerStyle(.segmented)

                if privacy == .privateList {
                    Label("The account names are protected so only you can read them.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                    Text("Other people may still be able to tell that a list was saved and roughly how large it is.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if selectedAccount?.isNC == true {
                        Label("This account cannot create a private list on this device.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                else {
                    Label("Anyone can see which accounts are blocked.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Combine safely") {
                exportCheckSection

                if !temporaryPubkeys.isEmpty {
                    MuteListCountRow("Temporary blocks skipped", count: temporaryPubkeys.count)
                    Text("Temporary blocks stay in Nostur because other apps would not know when to remove them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let statusMessage {
                    Label(statusMessage, systemImage: didPublish ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(didPublish ? .green : .orange)
                }

                if !didPublish, let checkedPreview {
                    Button(exportButtonTitle(checkedPreview), systemImage: "arrow.up.doc") {
                        export(checkedPreview)
                    }
                    .buttonStyleGlassProminent()
                    .disabled(
                        isPublishing
                        || !checkedPreview.canSafelyReplaceExistingList(privacy: privacy)
                        || (privacy == .privateList && selectedAccount?.isNC == true)
                    )
                }
            }
        }
        .navigationTitle("Export to relays")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selectedAccount = AccountsState.shared.fullAccounts.first {
                $0.publicKey == AccountsState.shared.activeAccountPublicKey
            } ?? AccountsState.shared.fullAccounts.first
            temporaryPubkeys = Set(CloudTask.fetchAll(byType: .blockUntil).map(\.value))
        }
        .onChange(of: selectedAccount?.publicKey) { _ in
            fetcher.state = .initializing
            statusMessage = nil
            didPublish = false
        }
        .confirmationDialog(
            "Publish without checking?",
            isPresented: $showPublishWithoutCheckConfirmation,
            titleVisibility: .visible
        ) {
            Button("Publish a new list", role: .destructive) {
                publishUncheckedNewList()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Nostur could not check whether this account already has a block list. Publishing may replace an existing list that could not be found.")
        }
    }

    @ViewBuilder
    private var exportCheckSection: some View {
        switch fetcher.state {
        case .initializing:
            Text("Nostur will first check what this account already saved, then combine it with your Nostur blocks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Check and prepare", systemImage: "arrow.triangle.2.circlepath") {
                checkExistingList()
            }
            .disabled(selectedAccount == nil)

        case .loading, .altLoading:
            HStack {
                ProgressView()
                Text("Checking existing blocks…")
            }

        case .ready(let preview):
            if preview.existingListStatus == .found {
                MuteListCountRow("Already saved", count: preview.existingPubkeys.count)
            }
            else if preview.existingListStatus == .notFound {
                Label("No existing block list found.", systemImage: "doc.badge.plus")
                    .foregroundStyle(.secondary)
            }
            else {
                Label("The existing block list could not be checked. Publishing may replace one that could not be found.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            MuteListCountRow("Permanent blocks in Nostur", count: exportPubkeys.count)
            MuteListCountRow("Total after combining", count: preview.combinedPubkeys.count)

            switch preview.privateContentStatus {
            case .decoded(let count) where count > 0:
                Text("\(count) existing private blocks are included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .keyUnavailable, .decryptionFailed:
                if privacy == .privateList {
                    Label("Some existing private items could not be read. Saving is disabled so they are not lost.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                else {
                    Label("Existing private items will be kept exactly as they are.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }

        case .timeout:
            Label("Nostur could not find an existing block list.", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            Button("Try again") { checkExistingList() }
            Button("Publish a new list anyway") {
                showPublishWithoutCheckConfirmation = true
            }
            .disabled(isPublishing)

        case .error(let message):
            Text(message).foregroundStyle(.red)
            Button("Try again") { checkExistingList() }
        }
    }

    private func exportButtonTitle(_ preview: MuteListExportPreview) -> LocalizedStringKey {
        guard !preview.existingListFound else { return "Publish combined list" }

        let count = preview.combinedPubkeys.count
        return count == 1
            ? "Publish a new list with 1 block"
            : "Publish a new list with \(count) blocks"
    }

    @MainActor
    private func publishUncheckedNewList() {
        guard let accountPubkey = selectedAccount?.publicKey else { return }
        export(MuteListExportPreview(
            accountPubkey: accountPubkey,
            existingPubkeys: [],
            combinedPubkeys: exportPubkeys,
            existingListStatus: .notConfirmed,
            privateContentStatus: .absent,
            existingSnapshot: nil
        ))
    }

    @MainActor
    private func checkExistingList() {
        guard let selectedAccount else { return }

        let accountPubkey = selectedAccount.publicKey
        let privateKey = selectedAccount.isNC ? nil : selectedAccount.privateKey
        let localPubkeys = exportPubkeys

        fetcher.setFetchParams((
            prio: false,
            req: { taskId in
                req(RM.getUserProfileKinds(pubkey: accountPubkey, subscriptionId: taskId, kinds: [NIP51MuteListCodec.kind]))
            },
            onComplete: { [weak fetcher] relayMessage, _ in
                bg().perform {
                    guard let fetcher else { return }

                    guard let event = Event.fetchReplacableEvent(
                        Int64(NIP51MuteListCodec.kind),
                        pubkey: accountPubkey,
                        context: bg()
                    ) else {
                        if relayMessage != nil {
                            fetcher.ready(MuteListExportPreview(
                                accountPubkey: accountPubkey,
                                existingPubkeys: [],
                                combinedPubkeys: localPubkeys,
                                existingListStatus: .notFound,
                                privateContentStatus: .absent,
                                existingSnapshot: nil
                            ))
                        }
                        else {
                            fetcher.timeout()
                        }
                        return
                    }

                    do {
                        let decoded = try NIP51MuteListCodec.decode(event.toNEvent(), privateKey: privateKey)
                        fetcher.ready(MuteListExportPreview(
                            accountPubkey: accountPubkey,
                            existingPubkeys: decoded.pubkeys,
                            combinedPubkeys: decoded.pubkeys.union(localPubkeys),
                            existingListStatus: .found,
                            privateContentStatus: decoded.privateContentStatus,
                            existingSnapshot: decoded.snapshot
                        ))
                    }
                    catch {
                        fetcher.error(error.localizedDescription)
                    }
                }
            },
            altReq: nil
        ))
        fetcher.fetch()
    }

    @MainActor
    private func export(_ preview: MuteListExportPreview) {
        guard let selectedAccount else { return }
        isPublishing = true
        statusMessage = nil
        let successMessage = preview.existingListFound ? "Combined list published" : "New list published"

        do {
            let privateKey = privacy == .privateList && !selectedAccount.isNC ? selectedAccount.privateKey : nil
            let event = try NIP51MuteListCodec.makeMergedUnsignedEvent(
                localPubkeys: exportPubkeys,
                authorPubkey: selectedAccount.publicKey,
                privacy: privacy,
                privateKey: privateKey,
                existing: preview.existingSnapshot
            )

            if selectedAccount.isNC {
                statusMessage = "Waiting for approval…"
                RemoteSignerManager.shared.requestSignature(forEvent: event, usingAccount: selectedAccount) { signedEvent in
                    DispatchQueue.main.async {
                        Unpublisher.shared.publishNow(signedEvent)
                        isPublishing = false
                        didPublish = true
                        statusMessage = successMessage
                    }
                }
            }
            else {
                let signedEvent = try selectedAccount.signEvent(event)
                Unpublisher.shared.publishNow(signedEvent)
                isPublishing = false
                didPublish = true
                statusMessage = successMessage
            }
        }
        catch {
            isPublishing = false
            statusMessage = error.localizedDescription
        }
    }
}

private struct MuteListCountRow: View {
    let title: LocalizedStringKey
    let count: Int

    init(_ title: LocalizedStringKey, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
        }
    }
}
