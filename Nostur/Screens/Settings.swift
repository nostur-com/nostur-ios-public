//
//  Settings.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import SwiftUI
import Combine
import CoreData
import Nuke
import NavigationBackport

struct Settings: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject private var settings: SettingsStore = .shared
    @AppStorage("devToggle") private var devToggle: Bool = false
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    @AppStorage("nip96_api_url") private var nip96ApiUrl = ""
    @Environment(\.managedObjectContext) var viewContext

    @State private var contactsCount:Int? = nil
    @State private var eventsCount:Int? = nil
    
    @State private var deleteAll = false
    @State private var showDeleteAllEventsConfirmation = false
    @State private var albyNWCsheetShown = false
    @State private var customNWCsheetShown = false
    @State private var showDefaultZapAmountSheet = false
    
//    @State var showDocPicker = false
    @State private var showExporter = false
    @State private var exportAccount:CloudAccount? = nil
    @State private var createRelayPresented = false
    
    private var fiatPrice:String {
        String(format: "$%.02f", (ceil(Double(settings.defaultZapAmount)) / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
    }
    
    @State var deleteAccountIsShown = false
    
    @State private var pfpSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var contentSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var bannerSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State private var badgesSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    
    @ObservedObject private var wot = WebOfTrust.shared
    
    @State private var isOptimizing = false
    @State private var dbNumberOfEvents = "-"
    @State private var dbNumberOfContacts = "-"
    
    
    @AppStorage("wotDunbarNumber") private var wotDunbarNumber: Int = 1000

    var body: some View {
        Form {
            Section(header: Text("Display", comment:"Setting heading on settings screen")) {
                Group {
                    #if DEBUG
                    Toggle(isOn: $settings.proMode) {
                        VStack(alignment: .leading) {
                            Text("Nostur Pro", comment:"Setting on settings screen")
                            Text("Multi-columns and more")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    #endif
                    
                    if #available(iOS 16, *) {
                        ThemePicker()
                    }

                    Toggle(isOn: $settings.fullWidthImages) {
                        Text("Enable full width pictures", comment:"Setting on settings screen")
                    }
                    VStack(alignment: .leading) {
                        AutodownloadLevelPicker()
                        
                        Text("Restrict auto-downloading of media posted by others")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle(isOn: $settings.animatedPFPenabled) {
                        VStack(alignment: .leading) {
                            Text("Enable animated profile pics", comment:"Setting on settings screen")
                            Text("Disable to improve scrolling performance", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    Toggle(isOn: $settings.rowFooterEnabled) {
                        VStack(alignment: .leading) {
                            Text("Show post stats on timeline", comment:"Setting on settings screen")
                            Text("Counters for replies, likes, zaps etc.", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $settings.displayUserAgentEnabled) {
                        VStack(alignment: .leading) {
                            Text("Show from which app someone posted", comment:"Setting on settings screen")
                            Text("Will show from which app/client something was posted, if available", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                                        
                    FooterConfiguratorLink() // Put NavigationLink in own view or freeze.
                }
                Toggle(isOn: $settings.fetchCounts) {
                    VStack(alignment: .leading) {
                        Text("Fetch counts on timeline", comment:"Setting on settings screen")
                        Text("Fetches like/zaps/replies counts as posts appear", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.autoScroll) {
                    VStack(alignment: .leading) {
                        Text("Auto scroll to new posts", comment:"Setting on settings screen")
                        Text("When at top, auto scroll if there are new posts", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.appWideSeenTracker) {
                    VStack(alignment: .leading) {
                        Text("Hide posts you have already seen (beta)", comment:"Setting on settings screen")
                        Text("Keeps track across all feeds posts you have already seen, don't show them again", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.autoHideBars) {
                    VStack(alignment: .leading) {
                        Text("Hide tab bars when scrolling", comment:"Setting on settings screen")
                        Text("This gives more screen space when scrolling")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.statusBubble) {
                    VStack(alignment: .leading) {
                        Text("Loading indicator", comment:"Setting on settings screen")
                        Text("Shows when items are being processed", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: $settings.hideBadges) {
                    VStack(alignment: .leading) {
                        Text("We Don't Need No Stinkin' Badges", comment:"Setting on settings screen")
                        Text("Hides badges from profiles and feeds", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
//                Toggle(isOn: $settings.hideEmojisInNames) {
//                    Text("Hide emojis in names", comment:"Setting on settings screen")
//                }
                Toggle(isOn: $settings.includeSharedFrom) {
                    VStack(alignment: .leading) {
                        Text("Include Nostur caption when sharing posts", comment:"Setting on settings screen")
                        Text("Shows 'Shared from Nostur' caption when sharing post screenshots", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(themes.theme.background)
            
            Group {
                Section(header: Text("Spam filtering", comment:"Setting heading on settings screen")) {
                    VStack(alignment: .leading) {
                        WebOfTrustLevelPicker()
                        
                        Text("Filter by your follows only (strict), or also your follows follows (normal)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        MainWoTaccountPicker()
                            .frame(maxHeight: 20)
                            .padding(.top, 5)
                        
                        if #available(iOS 16.0, *) {
                            Text("To log in with other accounts, but keep filtering using the main Web of Trust account")
                                .lineLimit(2, reservesSpace: true)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        else {
                            Text("To log in with other accounts, but keep filtering using the main Web of Trust account")
                                .lineLimit(2)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if (settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.normal.rawValue) {
                        VStack(alignment: .leading) {
                            Text("Nostr Dunbar Number")
                            Picker("Dunbar number", selection: $wotDunbarNumber) {
                                Text("250").tag(250)
                                Text("500").tag(500)
                                Text("1000").tag(1000)
                                Text("2000").tag(2000)
                                Text("♾️").tag(0)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            Text("Follow lists with a size higher than this threshold will be considered low quality and not included in your Web of Trust")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .onChange(of: wotDunbarNumber) { newValue in
                            bg().perform {
                                guard let account = account() else { return }
                                let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
                                wot.localReload(wotFollowingPubkeys: wotFollowingPubkeys)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Last updated: \(wot.lastUpdated?.formatted() ?? "Never")", comment: "Last updated date of WoT in Settings")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .onAppear {
                                bg().perform {
                                    wot.loadLastUpdatedDate()
                                }
                                if mainAccountWoTpubkey == "" {
                                    wot.guessMainAccount()
                                }
                            }
                        Spacer()
                        if wot.updatingWoT {
                            ProgressView()
                        }
                        else if mainAccountWoTpubkey != "" {
                            Button(String(localized:"Update", comment:"Button to update WoT")) {
                                guard !wot.updatingWoT else { return }
                                wot.updatingWoT = true
                                wot.loadWoT(force: true)
                            }
                        }
                    }
                    
                    Group {
                        if wot.allowedKeysCount == 0 || settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                            Text("Currently allowed by the filter: Everyone")
                        }
                        else {
                            Text("Currently allowed by the filter: \(wot.allowedKeysCount) contacts")
                        }
                    }.font(.caption).foregroundColor(.secondary)
                }
                .listRowBackground(themes.theme.background)
                
                Section(header: Text("Image uploading", comment:"Setting heading on settings screen")) {
                    MediaUploadServicePicker()
                    if !nip96ApiUrl.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Now using:")
                            Text(nip96ApiUrl)
                                .font(.caption)
                        }
                        .foregroundColor(themes.theme.secondary)
                    }
                }
                .listRowBackground(themes.theme.background)
            }
            
            Group {
                Section(header: Text("Zapping", comment:"Setting heading on settings screen")) {
                    
                    LightningWalletPicker()
                    
                    HStack {
                        Text("Default zap amount:")
                        Spacer()
                        Text("\(SettingsStore.shared.defaultZapAmount.clean) sats \(Image(systemName: "chevron.right"))")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showDefaultZapAmountSheet = true
                    }
                    .onChange(of: settings.defaultLightningWallet) { newWallet in
                        if newWallet.scheme == "nostur:nwc:alby:" {
                            // trigger alby setup
                            albyNWCsheetShown = true
                        }
                        else if newWallet.scheme == "nostur:nwc:custom:" {
                            // trigger custom NWC setup
                            customNWCsheetShown = true
                        }
                        else {
                            settings.activeNWCconnectionId = ""
                        }
                    }
                    
                    
                    if settings.nwcReady {
                        Toggle(isOn: $settings.nwcShowBalance) {
                            Text("Show wallet balance", comment:"Setting on settings screen")
                            Text("Will show balance in side bar", comment:"Setting on settings screen")
                        }
                        .onChange(of: settings.nwcShowBalance) { enabled in
                            if enabled {
                                nwcSendBalanceRequest()
                            }
                        }
                        
                        Picker(selection: $settings.thunderzapLevel) {
                            ForEach(ThunderzapLevel.allCases, id:\.self) {
                                Text($0.localized).tag($0.rawValue)
                                    .foregroundColor(themes.theme.primary)
                            }
                        } label: {
                            Text("Lightning sound effect", comment:"Setting on settings screen")
                        }
                        .pickerStyleCompatNavigationLink()
                    }
                }
                .listRowBackground(themes.theme.background)
                
                Section(header: Text("Posting", comment:"Setting heading on settings screen")) {
                    PostingToggle()
                }
                .listRowBackground(themes.theme.background)
                
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
                    .listRowBackground(themes.theme.background)
                }
                
                Section(header: Text("Relays", comment: "Relay settings heading")) {
                    RelaysView()
                    Button {
                        createRelayPresented = true
                    } label: {
                        Label("Add relay", systemImage: "plus")
                    }
                    .sheet(isPresented: $createRelayPresented) {
                        NewRelayView { url in
                            let relay = CloudRelay(context: viewContext)
                            relay.createdAt = Date()
                            relay.url_ = url
                            
                            do {
                                try viewContext.save()
                                if (relay.read || relay.write) {
                                    _ = ConnectionPool.shared.addConnection(relay.toStruct())
                                }
                            } catch {
                                L.og.error("Unresolved error \(error)")
                            }
                        }
                        .presentationBackgroundCompat(themes.theme.listBackground)
                        .environmentObject(themes)
                    }
                }
                .listRowBackground(themes.theme.background)
                
                RelayMasteryLink() // Wrapped in View else SwiftUI will freeze
                    .listRowBackground(themes.theme.background)
                
                Section(header: Text("Data usage", comment: "Setting heading on settings screen")) {
                    Toggle(isOn: $settings.lowDataMode) {
                        VStack(alignment: .leading) {
                            Text("Low Data mode", comment: "Setting on settings screen")
                            Text("Will not download media and previews", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    // TODO: add limited/primary relay selection
                }
                .listRowBackground(themes.theme.background)
                
                Section(header: Text("Caches", comment: "Settings heading")) {
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
                .listRowBackground(themes.theme.background)
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
            .listRowBackground(themes.theme.background)
            
            Section(header: Text("Message verification", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                    VStack(alignment: .leading) {
                        Text("Verify message signatures", comment: "Setting on settings screen")
                        Text("Turn off to save battery life and trust the relays for the authenticity of messages", comment:"Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(themes.theme.background)
            
            if account()?.privateKey != nil && !(account()?.isNC ?? false) {
                Section(header: Text("Account", comment: "Heading for section to delete account")) {
                    Button(role: .destructive) {
                        deleteAccountIsShown = true
                    } label: {
                        Label(String(localized:"Delete account", comment: "Button to delete account"), systemImage: "trash")
                    }                    
                }
                .listRowBackground(themes.theme.background)
            }
        }
        .sheet(isPresented: $showDefaultZapAmountSheet) {
            SettingsDefaultZapAmount()
                .environmentObject(themes)
                .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .scrollContentBackgroundHidden()
        .background(themes.theme.listBackground)
        .nosturNavBgCompat(themes: themes)
        .navigationTitle("Settings")
        .sheet(isPresented: $deleteAccountIsShown) {
            NBNavigationStack {
                DeleteAccountSheet()
                    .environmentObject(themes)
                    .environmentObject(NRState.shared)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .sheet(isPresented: $albyNWCsheetShown) {
            NBNavigationStack {
                AlbyNWCConnectSheet()
                    .environmentObject(themes)
                    .environmentObject(NRState.shared)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .sheet(isPresented: $customNWCsheetShown) {
            NBNavigationStack {
                CustomNWCConnectSheet()
                    .environmentObject(themes)
                    .environmentObject(NRState.shared)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
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

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadAccounts()
        }) {
            NBNavigationStack {
                Settings()
            }
        }
    }
}


protocol Localizable: RawRepresentable where RawValue: StringProtocol {}

extension Localizable {
    var localized: String {
        NSLocalizedString(String(rawValue), comment: "")
    }
}

struct FooterConfiguratorLink: View {
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        NavigationLink(destination: {
            FooterConfigurator(footerButtons: $settings.footerButtons)
        }, label: {
            HStack {
                Text("Reaction buttons")
                Spacer()
                Text(settings.footerButtons)
            }
        })
    }
}

struct RelayMasteryLink: View {
    @State private var relays:[CloudRelay] = []
    
    var body: some View {
        NavigationLink(destination: {
            RelayMastery(relays: relays)
                .onAppear {
                    relays = CloudRelay.fetchAll()
                }
        }, label: {
            Text("Relay Mastery")
        })
        .onAppear {
            
        }
    }
}
