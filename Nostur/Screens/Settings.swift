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

struct Settings: View {
    @EnvironmentObject var ns: NosturState
    @ObservedObject var settings: SettingsStore = .shared
    let er: ExchangeRateModel = .shared
    @AppStorage("devToggle") var devToggle: Bool = false
    @AppStorage("selected_tab") var selectedTab = "Main"
    @Environment(\.managedObjectContext) var viewContext
    let sp:SocketPool = .shared

    @State var contactsCount:Int? = nil
    @State var eventsCount:Int? = nil
    
    @FetchRequest(fetchRequest: Relay.fetchRequest())
    var allRelays:FetchedResults<Relay>
    
    @State var deleteAll = false
    @State var showDeleteAllEventsConfirmation = false
    @State var albyNWCsheetShown = false
    @State var customNWCsheetShown = false
    @State var showDefaultZapAmountSheet = false
    
//    @State var showDocPicker = false
    @State var showExporter = false
    @ObservedObject var vm = ViewPrint()
    @State var createRelayPresented = false
    
    @State var updatingWoT = false // to prevent double tapping
    
    var fiatPrice:String {
        String(format: "$%.02f", (ceil(Double(settings.defaultZapAmount)) / 100000000 * er.bitcoinPrice))
    }
    
    @State var deleteAccountIsShown = false
    
    @State var pfpSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State var contentSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State var bannerSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")
    @State var badgesSize = String(localized:"Calculating...", comment: "Shown when calculating disk space")

    var body: some View {

        Form {

            Section(header: Text("Display", comment:"Setting heading on settings screen")) {
                Group {
                    Toggle(isOn: $settings.fullWidthImages) {
                        Text("Enable full width pictures", comment:"Setting on settings screen")
                    }
                    Toggle(isOn: $settings.restrictAutoDownload) {
                        Text("Restrict images to following", comment:"Setting on settings screen")
                        Text("Only auto-download images in new posts from people you follow\nToggle off to download from all", comment:"Setting on settings screen")
                    }
                    
                    Toggle(isOn: $settings.animatedPFPenabled) {
                        Text("Enable animated profile pics", comment:"Setting on settings screen")
                        Text("Disable to improve scrolling performance", comment:"Setting on settings screen")
                    }
                    Toggle(isOn: $settings.rowFooterEnabled) {
                        Text("Show post stats on timeline", comment:"Setting on settings screen")
                        Text("Counters for replies, likes, zaps etc.", comment:"Setting on settings screen")
                    }
                }
                Toggle(isOn: $settings.fetchCounts) {
                    Text("Fetch counts on timeline", comment:"Setting on settings screen")
                    Text("Fetches like/zaps/replies counts as posts appear", comment:"Setting on settings screen")
                }
                Toggle(isOn: $settings.autoScroll) {
                    Text("Auto scroll to new posts", comment:"Setting on settings screen")
                    Text("When at top, auto scroll if there are new posts", comment:"Setting on settings screen")
                }
                Toggle(isOn: $settings.autoHideBars) {
                    Text("Hide tab bars when scrolling", comment:"Setting on settings screen")
                    Text("This gives more screen space when scrolling")
                }
                Toggle(isOn: $settings.statusBubble) {
                    Text("Loading indicator", comment:"Setting on settings screen")
                    Text("Shows when items are being processed", comment:"Setting on settings screen")
                }
                Toggle(isOn: $settings.hideBadges) {
                    Text("We Don't Need No Stinkin' Badges", comment:"Setting on settings screen")
                    Text("Hides badges from profiles and feeds", comment: "Setting on settings screen")
                }
                Toggle(isOn: $settings.hideEmojisInNames) {
                    Text("Hide emojis in names", comment:"Setting on settings screen")
                }
                Toggle(isOn: $settings.includeSharedFrom) {
                    Text("Include Nostur caption when sharing posts", comment:"Setting on settings screen")
                    Text("Shows 'Shared from Nostur' caption when sharing post screenshots", comment: "Setting on settings screen")
                }
            }
            
            Group {
                Section(header: Text("Spam filtering", comment:"Setting heading on settings screen")) {
                    VStack {
                        Picker(selection: $settings.webOfTrustLevel) {
                            ForEach(SettingsStore.WebOfTrustLevel.allCases, id:\.self) {
                                Text($0.localized).tag($0.rawValue)
                            }
                        } label: {
                            Text("Web of Trust filter", comment:"Setting on settings screen")
                        }
                        .onChange(of: settings.webOfTrustLevel) { newValue in
                            if newValue == SettingsStore.WebOfTrustLevel.normal.rawValue {
                                DataProvider.shared().bg.perform {
                                    NosturState.shared.wot?.loadNormal()
                                }
                            }
                        }
                    }
                    Text("Filter by your follows only (strict), or also your follows follows (normal)").font(.caption).foregroundColor(.gray)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Updated: \(NosturState.shared.wot?.lastUpdated?.formatted() ?? "Never")", comment: "Last updated date of WoT in Settings")
                                .onAppear {
                                    DataProvider.shared().bg.perform {
                                        NosturState.shared.wot?.loadLastUpdatedDate()
                                    }
                                }
                            if settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                                Text("Allowed: Everyone")
                            }
                            else if let count = NosturState.shared.wot?.allowedKeysCount {
                                Text("Allowed: \(count) contacts")
                            }
                        }
                        Spacer()
                        Button(String(localized:"Update", comment:"Button to update WoT")) {
                            guard updatingWoT == false else { return }
                            updatingWoT = true
                            DataProvider.shared().bg.perform {
                                NosturState.shared.wot?.loadNormal()
                            }
                        }
                    }
                }
                
                Section(header: Text("Image uploading", comment:"Setting heading on settings screen")) {
                    VStack {
                        Picker(selection: $settings.defaultMediaUploadService) {
                            ForEach(SettingsStore.mediaUploadServiceOptions) {
                                Text($0.name).tag($0)
                            }
                        } label: {
                            Text("Media upload service", comment:"Setting on settings screen")
                        }
                    }
                }
            }
            
            Group {
                Section(header: Text("Zapping", comment:"Setting heading on settings screen")) {
                    
                    VStack(alignment: .leading) {
                        Picker(selection: $settings.defaultLightningWallet) {
                            ForEach(SettingsStore.walletOptions) {
                                Text($0.name).tag($0)
                            }
                        } label: {
                            Text("Lightning wallet", comment:"Setting on settings screen")
                            Text("Choose which wallet to use for zapping", comment:"Setting on settings screen")
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Default zap amount:")
                            Spacer()
                            Text("\(SettingsStore.shared.defaultZapAmount.clean) sats \(Image(systemName: "chevron.right"))")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showDefaultZapAmountSheet = true
                        }
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
                }
                
                Section(header: Text("Data export")) {
                    Button("Save to file...") {
                        guard ns.account != nil else { L.og.error("Cannot export, no account"); return }
                        showExporter.toggle()
                    }
                    if (showExporter) {
                        Color.clear
                            .fileExporter(isPresented: $showExporter, document: EventsArchive(pubkey: ns.account!.publicKey), contentType: .events, defaultFilename: "Exported Nostur Events - \(String(ns.account!.npub.prefix(11)))") { result in
                                switch result {
                                case .success(let url):
                                    L.og.info("Saved to \(url)")
                                case .failure(let error):
                                    print(error.localizedDescription)
                                }
                            }
                    }
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
                            let relay = Relay(context: viewContext)
                            relay.id = UUID()
                            relay.createdAt = Date()
                            relay.url = url
                            
                            do {
                                try viewContext.save()
                                if (relay.read || relay.write) {
                                    _ = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relay.url!, read: relay.read, write: relay.write)
                                }
                            } catch {
                                L.og.error("Unresolved error \(error)")
                            }
                        }
                    }
                }
                
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
                
            }
            
            Section(header: Text("Message verification", comment: "Setting heading on settings screen")) {
                Toggle(isOn: $settings.isSignatureVerificationEnabled) {
                    Text("Verify message signatures", comment: "Setting on settings screen")
                    Text("Turn off to save battery life and trust the relays for the authenticity of messages", comment:"Setting on settings screen")
                }
            }
            
//            Section(header: Text("Dev")) {
//                Toggle(isOn: $devToggle) {
//                    VStack(alignment: .leading) {
//                        Text("Dev mode")
//                        if (devToggle) {
//                            Text(vm.throttleText)
//                        }
//                    }
//                }.padding(10)
//                if (devToggle) {
//                    VStack(alignment: .leading) {
//                        Group {
//
//                            Button { removeOlderKind3Events() } label: {
//                                Text("Remove old contact lists (kind=3)")
//                            }
//
//                            Button { Maintenance.maintenance(context: viewContext) } label: {
//                                Text("Clean up older than 3 days")
//                            }
//
//                            Button { fixPointers() } label: {
//                                Text("Rebuild referenced things (tagsSerialized -> someId, anotherId)")
//                            }
//
//                            Button { rebuildCountingCache() } label: {
//                                Text("Rebuild counter cache (likes, mentions, replies, zaps)")
//                            }
//
//                            Button { rebuildContactCache() } label: {
//                                Text("Rebuild contact cache (banner, picture etc)")
//                            }
//                        }
//                        .buttonStyle(.bordered)
//
//
//                        Group {
//                            Button { deleteAll = true } label: {
//                                Text("Delete all contacts \(contactsCount?.description ?? "")")
//                            }.confirmationDialog("SURE???", isPresented: $deleteAll, actions: {
//                                Button("YES DELETE ALL CONTACTS", role: .destructive) { deleteAllContacts() }
//                            })
//
//                            Button { showDeleteAllEventsConfirmation = true } label: {
//                                Text("Delete all events \(eventsCount?.description ?? "")")
//                            }.confirmationDialog("DELETE ALL EVENTS????", isPresented: $showDeleteAllEventsConfirmation) {
//                                Button("YES DELETE ALL EVENTS", role: .destructive) {
//                                    deleteAllEvents()
//                                }
//                            }
//
//                            Button { fixContactEventRelations() } label: {
//                                Text("Fix event.pubkey -> event.contact")
//                            }
//
//                            Button { putContactsInEventsForPs() } label: {
//                                Text("Fix contacts (p) in event")
//                            }
//
//                            Button { fixRelations() } label: { Text("Fix relations (replyToId -> replyTo) etc") }
//
//                            Button { clearImageCache()} label: {
//                                Text("Clear image cache")
//                            }
//                        }
//                        .buttonStyle(.bordered)
//                    }
//                }
//            }
//                Section(header: Text("Private key protector")) {
//                    Toggle(isOn: $settings.replaceNsecWithHunter2Enabled) {
//                        Text("Don't allow nsec in posts")
//                        Text("Replaces any \"nsec1...\" in new posts with \"hunter2\" ")
//                    }
//                }
            if ns.account?.privateKey != nil && !(ns.account?.isNC ?? false) {
                Section(header: Text("Account", comment: "Heading for section to delete account")) {
                    Button(role: .destructive) {
                        deleteAccountIsShown = true
                    } label: {
                        Label(String(localized:"Delete account", comment: "Button to delete account"), systemImage: "trash")
                    }                    
                }
            }
        }
        .sheet(isPresented: $showDefaultZapAmountSheet) {
            SettingsDefaultZapAmount()
        }
        .onAppear {
            let bg = DataProvider.shared().container.newBackgroundContext()
            bg.perform {
                let r = Event.fetchRequest()
                r.resultType = .countResultType
                let eventsCount = (try? bg.count(for: r)) ?? 0
                
                let c = Contact.fetchRequest()
                c.resultType = .countResultType
                let contactsCount = (try? bg.count(for: c)) ?? 0
                
                DispatchQueue.main.async {
                    self.contactsCount = contactsCount
                    self.eventsCount = eventsCount
                }
            }
            
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $deleteAccountIsShown) {
            NavigationStack {
                DeleteAccountSheet()
                    .environmentObject(ns)
            }
        }
        .sheet(isPresented: $albyNWCsheetShown) {
            NavigationStack {
                AlbyNWCConnectSheet()
                    .environmentObject(ns)
            }
        }
        .sheet(isPresented: $customNWCsheetShown) {
            NavigationStack {
                CustomNWCConnectSheet()
                    .environmentObject(ns)
            }
        }
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            Settings()
        }
    }
}


protocol Localizable: RawRepresentable where RawValue: StringProtocol {}

extension Localizable {
    var localized: String {
        NSLocalizedString(String(rawValue), comment: "")
    }
}
