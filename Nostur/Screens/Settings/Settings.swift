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
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var network: NetworkMonitor = .shared
    @AppStorage("devToggle") private var devToggle: Bool = false
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    @AppStorage("nip96_api_url") private var nip96ApiUrl = ""
    @AppStorage("media_upload_service") private var mediaUploadService = ""
    @Environment(\.managedObjectContext) var viewContext

    @State private var contactsCount:Int? = nil
    @State private var eventsCount:Int? = nil
    
    @State private var deleteAll = false
    @State private var showDeleteAllEventsConfirmation = false
    @State private var albyNWCsheetShown = false
    @State private var customNWCsheetShown = false
    @State private var showDefaultZapAmountSheet = false
    @State private var blossomConfiguratorShown = false
    
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
    
    @State private var notInWoTcount = 0
    @State private var notInWoTLastHours = 0
    
    @AppStorage("wotDunbarNumber") private var wotDunbarNumber: Int = 1000

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        NXForm {
            Section(header: Text("Display", comment:"Setting heading on settings screen")) {
                Group {
                    if IS_CATALYST {
                        Toggle(isOn: $settings.proMode) {
                            VStack(alignment: .leading) {
                                Text("Nostur Pro", comment:"Setting on settings screen")
                                Text("Multi-columns and more")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if #available(iOS 16, *) {
                        ThemePicker()
                    }

                    if !AVAILABLE_26 { // Starting 26.0, full width is always on
                        Toggle(isOn: $settings.fullWidthImages) {
                            Text("Enable full width pictures", comment:"Setting on settings screen")
                        }
                    }
                    
                    Toggle(isOn: $settings.enableLiveEvents) {
                        Text("Show Live banner", comment:"Setting on settings screen")
                        Text("Live Nests or streams from follows")
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
                if settings.appWideSeenTracker && FileManager.default.ubiquityIdentityToken != nil {
                    Toggle(isOn: $settings.appWideSeenTrackeriCloud) {
                        VStack(alignment: .leading) {
                            Text("Hide posts you have already seen on multiple devices", comment:"Setting on settings screen")
                            Text("Uses iCloud to sync across devices", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
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

                Toggle(isOn: $settings.includeSharedFrom) {
                    VStack(alignment: .leading) {
                        Text("Include Nostur caption when sharing posts", comment:"Setting on settings screen")
                        Text("Shows 'Shared from Nostur' caption when sharing post screenshots", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $settings.enableOutboxPreview) {
                    VStack(alignment: .leading) {
                        Text("Show extra relays used on post preview", comment: "Setting on settings screen")
                        Text("If Relay Autopilot is enabled show which additional relays will be used", comment: "Setting on settings screen")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(theme.background)
            
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
                                .onAppear {
                                    bg().perform {
                                        if ConnectionPool.shared.notInWoTcount > 0 {
                                            let notInWoTsince = ConnectionPool.shared.notInWoTsince
                                            let notInWoTcount = ConnectionPool.shared.notInWoTcount
                                            
                                            let lastHours: Int = {
                                                let calendar = Calendar.current
                                                let components = calendar.dateComponents([.hour], from: notInWoTsince, to: Date())
                                                return components.hour ?? 0
                                            }()
                                            
                                            Task { @MainActor in
                                                self.notInWoTcount = notInWoTcount
                                                self.notInWoTLastHours = lastHours
                                            }
                                        }
                                    }
                                }
                            
                            if notInWoTcount != 0 {
                                Text("Spam filtered in the last \(notInWoTLastHours > 1 ? "\(notInWoTLastHours) hours" : "hour"): \(notInWoTcount) items")
                            }
                        }
                    }.font(.caption).foregroundColor(.secondary)
                }
                .listRowBackground(theme.background)
                
                Section(header: Text("Media uploading", comment:"Setting heading on settings screen")) {
                    
                    MediaUploadServicePicker()
                    
                    if !nip96ApiUrl.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Now using:")
                            Text(nip96ApiUrl)
                                .font(.caption)
                        }
                        .foregroundColor(theme.secondary)
                    }
                    
                    if mediaUploadService == BLOSSOM_LABEL {
                        Button("Configure blossom server(s)") {
                            blossomConfiguratorShown = true
                        }
                        .sheet(isPresented: $blossomConfiguratorShown) {
                            NBNavigationStack {
                                BlossomServerList()
                                    .environment(\.theme, theme)
                                    .presentationBackgroundCompat(theme.listBackground)
                            }
                            .nbUseNavigationStack(.never)
                            .presentationBackgroundCompat(theme.listBackground)
                        }
                    }
                }
                .listRowBackground(theme.background)
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
                        else if newWallet.scheme.starts(with: "nostur:nwc:last:") {

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
                                    .foregroundColor(theme.primary)
                            }
                        } label: {
                            Text("Lightning sound effect", comment:"Setting on settings screen")
                        }
                        .pickerStyleCompatNavigationLink()
                    }
                }
                .listRowBackground(theme.background)
                
                Section(header: Text("Posting", comment:"Setting heading on settings screen")) {
                    PostingToggle()
                }
                .listRowBackground(theme.background)
                
                Section(header: Text("Relays", comment: "Relay settings heading")) {
                    RelaysLink()
                        .listRowBackground(theme.background)
                    
                    RelayMasteryLink() // Wrapped in View else SwiftUI will freeze
                        .listRowBackground(theme.background)
                    
                    Toggle(isOn: $settings.enableOutboxRelays) {
                        VStack(alignment: .leading) {
                            Text("Autopilot", comment: "Setting on settings screen")
                            Text("Automatically connect to additional relays from people you follow to reduce missing content that can't be found on your own relay set", comment: "Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settings.enableOutboxRelays) { newValue in
                        guard newValue == true, let loggedInAccount = AccountsState.shared.loggedInAccount, loggedInAccount.outboxLoader == nil else { return }
                        loggedInAccount.outboxLoader = OutboxLoader(pubkey: loggedInAccount.pubkey, follows: loggedInAccount.viewFollowingPublicKeys, cp: ConnectionPool.shared)
                    }
          
                    
                    Toggle(isOn: $settings.followRelayHints) {
                        VStack(alignment: .leading) {
                            Text("Follow relay hints", comment: "Setting on settings screen")
                            Text("Connect to relays included in nostr links when content can't be found", comment:"Setting on settings screen")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    if settings.enableOutboxRelays || settings.followRelayHints {
                        Toggle(isOn: $settings.enableVPNdetection) {
                            VStack(alignment: .leading) {
                                Text("VPN detection", comment: "Setting on settings screen")
                                Text("Only connect to additional relays when a VPN is active")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                
                                if network.vpnDetected {
                                    HStack(spacing: 3) {
                                        Image(systemName: "circle.fill").foregroundColor(.green)
                                        Text("VPN detected")
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.footnote)
                                }
                                else {
                                    HStack(spacing: 3) {
                                        Image(systemName: "circle.fill").foregroundColor(.red)
                                        Text("VPN not detected")
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.footnote)
                                }
                            }
                        }
                        .onChange(of: settings.enableVPNdetection) { newValue in
                            if newValue {
                                NetworkMonitor.shared.detectActualConnection()
                            }
                        }
                    }
                    
                    RelaysStatsLink()
                        .listRowBackground(theme.background)
                    
                }
                .listRowBackground(theme.background)
                
                
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
                .listRowBackground(theme.background)
                
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
                .listRowBackground(theme.background)
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
            .listRowBackground(theme.background)
            
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
            .listRowBackground(theme.background)
            
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
            
            if account()?.privateKey != nil && !(account()?.isNC ?? false) {
                Section(header: Text("Account", comment: "Heading for section to delete account")) {
                    Button(role: .destructive) {
                        deleteAccountIsShown = true
                    } label: {
                        Label(String(localized:"Delete account", comment: "Button to delete account"), systemImage: "trash")
                    }                    
                }
                .listRowBackground(theme.background)
            }
        }
        .sheet(isPresented: $showDefaultZapAmountSheet) {
            NBNavigationStack {
                SettingsDefaultZapAmount()
                    .environment(\.theme, theme)
                    .presentationBackgroundCompat(theme.listBackground)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
//        .scrollContentBackgroundHidden()
//        .background(theme.listBackground)
        .nosturNavBgCompat(theme: theme)
        .navigationTitle("Settings")
        .sheet(isPresented: $deleteAccountIsShown) {
            NRNavigationStack {
                DeleteAccountSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $albyNWCsheetShown) {
            NRNavigationStack {
                AlbyNWCConnectSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
        }
        .sheet(isPresented: $customNWCsheetShown) {
            NRNavigationStack {
                CustomNWCConnectSheet()
            }
            .environmentObject(la)
            .presentationBackgroundCompat(theme.listBackground)
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
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    
    var body: some View {
        NavigationLink(destination: {
            FooterConfigurator(footerButtons: $settings.footerButtons)
                .background(theme.listBackground)
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
    @Environment(\.theme) private var theme
    @State private var relays: [CloudRelay] = []
    
    var body: some View {
        NavigationLink(destination: {
            RelayMastery(relays: relays)
                .presentationBackgroundCompat(theme.listBackground)
                .onAppear {
                    relays = CloudRelay.fetchAll()
                }
        }, label: {
            VStack(alignment: .leading) {
                Text("Announce your relays...")
                Text("Relays others will use to find your content")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        })
    }
}


struct RelaysLink: View {
    @Environment(\.theme) private var theme
    
    var body: some View {
        NavigationLink(destination: {
            RelaysView()
                .presentationBackgroundCompat(theme.listBackground)
        }, label: {
            VStack(alignment: .leading) {
                Text("Configure your relays...")
                Text("Relays Nostur uses to find or publish content")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        })
    }
}

struct RelaysStatsLink: View {
    @Environment(\.theme) private var theme
    var body: some View {
        NavigationLink(destination: {
            RelayStatsView(stats: ConnectionPool.shared.connectionStats)
                .presentationBackgroundCompat(theme.listBackground)
        }, label: {
            VStack(alignment: .leading) {
                Text("Relay connection stats")
            }
        })
    }
}
