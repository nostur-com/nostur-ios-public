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
}

#Preview {
    DatabaseAndCacheSettings()
}
