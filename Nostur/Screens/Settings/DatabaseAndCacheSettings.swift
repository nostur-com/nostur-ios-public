//
//  DatabaseAndCacheSettings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import Nuke

struct DatabaseAndCacheSettings: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared

    @State private var pfpSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var contentSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var bannerSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var badgesSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var dmFilesSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")

    @State private var isOptimizing = false
    @State private var dbNumberOfEvents = "-"
    @State private var dbNumberOfContacts = "-"
    
    @State private var showExporter = false
    @State private var exportAccount: CloudAccount? = nil
    
    var body: some View {
        NXForm {
            Section(header: Text("Media cache", comment: "Settings heading")) {
                HStack {
                    Text("Profile pictures: \(pfpSize)", comment: "Message showing size of Profile pictures cache")
                        .task(priority: .medium) {
                            let cache = ImageProcessing.shared.pfp.configuration.dataCache as! DataCache
                            pfpSize = "\((cache.totalSize / 1024 / 1024)) MB"
                        }
                    Spacer()
                    Button(String(localized:"Clear", comment:"Button to clear cache")) {
                        pfpSize = String(localized: "Clearing...", comment:"Message shown when clearing cache")
                        Task.detached(priority: .userInitiated) {
                            let cache = ImageProcessing.shared.pfp.configuration.dataCache as! DataCache
                            cache.removeAll()
                            cache.flush()
                            Task { @MainActor in
                                pfpSize = "\((cache.totalSize / 1024 / 1024)) MB"
                                settings.objectWillChange.send()
                            }
                        }
                    }
                }
                HStack {
                    Text("Post content: \(contentSize)", comment: "Message showing size of Post content cache")
                        .task(priority: .medium) {
                            let cache = ImageProcessing.shared.content.configuration.dataCache as! DataCache
                            contentSize = "\((cache.totalSize / 1024 / 1024)) MB"
                        }
                    Spacer()
                    Button(String(localized:"Clear", comment:"Button to clear cache")) {
                        contentSize = String(localized: "Clearing...", comment:"Message shown when clearing cache")
                        Task.detached(priority: .userInitiated) {
                            let cache = ImageProcessing.shared.content.configuration.dataCache as! DataCache
                            cache.removeAll()
                            cache.flush()
                            Task { @MainActor in
                                contentSize = "\((cache.totalSize / 1024 / 1024)) MB"
                                settings.objectWillChange.send()
                            }
                        }
                    }
                }
                HStack {
                    Text("Profile banners: \(bannerSize)", comment: "Message showing size of Profile banners cache")
                        .task(priority: .medium) {
                            let cache = ImageProcessing.shared.banner.configuration.dataCache as! DataCache
                            bannerSize = "\((cache.totalSize / 1024 / 1024)) MB"
                        }
                    Spacer()
                    Button(String(localized:"Clear", comment:"Button to clear cache")) {
                        bannerSize = String(localized: "Clearing...", comment:"Message shown when clearing cache")
                        Task.detached(priority: .userInitiated) {
                            let cache = ImageProcessing.shared.banner.configuration.dataCache as! DataCache
                            cache.removeAll()
                            cache.flush()
                            Task { @MainActor in
                                bannerSize = "\((cache.totalSize / 1024 / 1024)) MB"
                                settings.objectWillChange.send()
                            }
                        }
                    }
                }
                HStack {
                    Text("Badges: \(badgesSize)", comment: "Message showing size of badges cache")
                        .task(priority: .medium) {
                            let cache = ImageProcessing.shared.badges.configuration.dataCache as! DataCache
                            badgesSize = "\((cache.totalSize / 1024 / 1024)) MB"
                        }
                    Spacer()
                    Button(String(localized:"Clear", comment:"Button to clear cache")) {
                        badgesSize = String(localized: "Clearing...", comment:"Message shown when clearing cache")
                        Task.detached(priority: .userInitiated) {
                            let cache = ImageProcessing.shared.badges.configuration.dataCache as! DataCache
                            cache.removeAll()
                            cache.flush()
                            Task { @MainActor in
                                badgesSize = "\((cache.totalSize / 1024 / 1024)) MB"
                                settings.objectWillChange.send()
                            }
                        }
                    }
                }
                NavigationLink {
                    DMFileCacheSettings()
                } label: {
                    HStack {
                        Text("DM files and media")
                        Spacer()
                        Text(dmFilesSize)
                            .foregroundStyle(.secondary)
                    }
                }
                .task {
                    dmFilesSize = Self.formattedBytes(await DMFileCache.shared.totalSize())
                }

            }
            
            Section(header: Text("Database status", comment: "Settings heading")) {
                HStack {
                    Text("Nostr events:")
                    Spacer()
                    Text(dbNumberOfEvents)
                }
                .onAppear {
                    countDbEvents()
                }
                
                HStack {
                    Text("Contacts:")
                    Spacer()
                    Text(dbNumberOfContacts)
                }
                .onAppear {
                    countDbContacts()
                }
                
                HStack {
                    Text("Last optimize: \(SettingsStore.shared.lastMaintenanceTimestamp != 0 ? Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp)).formatted() : "Never")", comment: "Last run: (date) of maintanace")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    if isOptimizing {
                        ProgressView()
                    }
                    else {
                        Button(String(localized: "Optimize now", comment:"Button to run database clean up now")) {
                            isOptimizing = true
                            Task {
                                let didRun = await Maintenance.dailyMaintenance(context: bg(), force: true)
                                if didRun {
                                    await Importer.shared.preloadExistingIdsCache()
                                    DispatchQueue.main.async {
                                        countDbEvents()
                                        countDbContacts()
                                    }
                                }
                                Task { @MainActor in
                                    isOptimizing = false
                                }
                            }
                        }
                    }
                }
            }
            
            if #available(iOS 16, *) {
                Section(header: Text("Data export")) {
                    Button("Save to file...") {
                        guard let account = account() else { L.og.error("Cannot export, no account"); return }
                        exportAccount = account
                        showExporter.toggle()
                    }
                    if let exportAccount = exportAccount, showExporter == true {
                        Color.clear
                            .fileExporter(isPresented: $showExporter, document: EventsArchive(pubkey: exportAccount.publicKey), contentType: .events, defaultFilename: "Exported Nostur Events - \(String(exportAccount.npub.prefix(11)))") { result in
                                switch result {
                                case .success(let url):
                                    L.og.info("Saved to \(url)")
                                case .failure(let error):
                                    L.og.debug("Export: \(error.localizedDescription)")
                                }
                            }
                    }
                }
                .listRowBackground(theme.background)
            }
        }
    }
    
    private func countDbEvents() {
        dbNumberOfEvents = Importer.shared.existingIds.count.formatted()
    }
    
    private func countDbContacts() {
        bg().perform {
            let fr = Contact.fetchRequest()
            fr.resultType = .countResultType
            let count = (try? bg().count(for: fr)) ?? 0
            DispatchQueue.main.async {
                dbNumberOfContacts = count.formatted()
            }
        }
    }

    fileprivate static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct DMFileCacheSettings: View {
    @State private var conversations: [DMFileCache.ConversationUsage] = []
    @State private var isClearing = false
    @State private var showClearAllConfirmation = false
    @AppStorage(DMFileCache.maxSizeKey) private var dmFileCacheMaxSizeMB = DMFileCache.defaultMaxSizeMB

    var body: some View {
        NXForm {
            Section {
                Picker("Maximum disk usage", selection: $dmFileCacheMaxSizeMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1_024)
                    Text("2 GB").tag(2_048)
                    Text("5 GB").tag(5_120)
                    Text("10 GB").tag(10_240)
                    Text("25 GB").tag(25_600)
                    Text("50 GB").tag(51_200)
                }
                .onChange(of: dmFileCacheMaxSizeMB) { _ in
                    Task {
                        await DMFileCache.shared.trimIfNeeded()
                        await reload()
                    }
                }
            } header: {
                Text("Cache limit")
            }

            Section {
                if conversations.isEmpty {
                    Text("No downloaded DM files")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(conversations) { conversation in
                        DMFileCacheConversationRow(usage: conversation) {
                            await reload()
                        }
                    }
                }
            } header: {
                Text("Usage by conversation")
            } footer: {
                Text("Kept conversations do not count toward automatic cleanup, but their size is included in the total.")
            }

            Section {
                Button(role: .destructive) {
                    showClearAllConfirmation = true
                } label: {
                    HStack {
                        Text("Clear DM files (kept conversations excluded)")
                        if isClearing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isClearing || conversations.allSatisfy(\.isKept))
            }
        }
        .navigationTitle("DM disk usage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .confirmationDialog(
            "Clear all non-kept DM files?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all non-kept files", role: .destructive) {
                isClearing = true
                Task {
                    try? await DMFileCache.shared.clearAllExceptKept()
                    await reload()
                    isClearing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all downloaded files and media from conversations that are not marked Keep. The messages themselves will not be deleted.")
        }
    }

    @MainActor
    private func reload() async {
        conversations = await DMFileCache.shared.usage()
    }
}

private struct DMFileCacheConversationRow: View {
    let usage: DMFileCache.ConversationUsage
    let didChange: () async -> Void
    @State private var isKept: Bool
    @State private var isClearing = false
    @State private var showClearConfirmation = false

    init(usage: DMFileCache.ConversationUsage, didChange: @escaping () async -> Void) {
        self.usage = usage
        self.didChange = didChange
        _isKept = State(initialValue: usage.isKept)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversationTitle)
                        .lineLimit(1)
                    Text("\(usage.fileCount) \(usage.fileCount == 1 ? "file" : "files") · \(DatabaseAndCacheSettings.formattedBytes(usage.bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(isClearing)
            }
            Toggle("Keep files permanently", isOn: $isKept)
                .font(.footnote)
                .onChange(of: isKept) { newValue in
                    Task {
                        await DMFileCache.shared.setKept(newValue, conversationId: usage.id)
                        if !newValue { await DMFileCache.shared.trimIfNeeded() }
                        await didChange()
                    }
                }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Clear downloaded files?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear downloaded files", role: .destructive) {
                isClearing = true
                Task {
                    try? await DMFileCache.shared.clear(conversationId: usage.id)
                    await didChange()
                    isClearing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all downloaded files and media for this conversation.")
        }
    }

    private var conversationTitle: String {
        let pubkeys = stride(from: 0, to: usage.id.count, by: 64).compactMap { offset -> String? in
            guard usage.id.count >= offset + 64 else { return nil }
            let start = usage.id.index(usage.id.startIndex, offsetBy: offset)
            let end = usage.id.index(start, offsetBy: 64)
            return String(usage.id[start..<end])
        }
        let ourPubkey = account()?.publicKey
        let others = pubkeys.filter { $0 != ourPubkey }
        if others.count == 1, let pubkey = others.first {
            return NRContact.instance(of: pubkey).anyName
        }
        if !others.isEmpty {
            return others.map { NRContact.instance(of: $0).anyName }.joined(separator: ", ")
        }
        return String(usage.id.prefix(12)) + "…"
    }
}

#Preview {
    DatabaseAndCacheSettings()
}
