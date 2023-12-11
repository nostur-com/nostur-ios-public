//
//  AppView.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/05/2023.
//

import SwiftUI
import Combine
import CoreData
import Nuke
import AVFoundation

/// The main app view
///
/// Shows one of 3: Onboarding, Main app screen, or Critical database failure preventing the app from loading further
struct AppView: View {
    @EnvironmentObject private var ns:NRState
    @EnvironmentObject private var networkMonitor:NetworkMonitor
    @EnvironmentObject private var dm:DirectMessageViewModel
    @EnvironmentObject private var nvm:NotificationsViewModel
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    // These singletons always exists during the apps lifetime
    @State private var tm:DetailTabsModel = .shared
    @State private var er:ExchangeRateModel = .shared
    @State private var eventRelationsQueue:EventRelationsQueue = .shared
    @State private var lvmManager:LVMManager = .shared
    @State private var queuedFetcher:QueuedFetcher = .shared
    @State private var mp:MessageParser = .shared
    @State private var zpvq:ZapperPubkeyVerificationQueue = .shared
    @State private var nip05verifier:NIP05Verifier = .shared
    @State private var ip:ImageProcessing = .shared
    @State private var avcache:AVAssetCache = .shared
    @State private var idr:ImageDecoderRegistry = .shared
    
    @State private var kind0:Kind0Processor = .shared
    @State private var nwcRQ:NWCRequestQueue = .shared
    @State private var ot:NewOnboardingTracker = .shared
    @State private var dd:Deduplicator = .shared
    @State private var vmc:ViewModelCache = .shared
    
//    @EnvironmentObject private var themes:Themes
    @AppStorage("firstTimeCompleted") private var firstTimeCompleted = false
    @AppStorage("did_accept_terms") private var didAcceptTerms = false
    
    
//    @State private var isViewDisplayed = false
    @State private var isOnboarding = false
    
    @State private var priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))
    
    @StateObject private var themes:Themes = .default
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])
    private var accounts:FetchedResults<CloudAccount>
    
    @State private var noAccounts = false
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.markedReadAt_, order: .reverse)])
    private var dmStates:FetchedResults<CloudDMState>
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.updatedAt_, order: .reverse)])
    private var relays:FetchedResults<CloudRelay>
    
    @State private var noDMStates = false
    
    @State private var didRemoveDuplicateRelays = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Group {
            if DataProvider.shared().databaseProblem {
                VStack {
                    Text("Something went wrong")
                        .font(.title2)
                    Text("The database could not be loaded.")
                        .padding(.bottom, 20)
                    Text("Sorry, this was not supposed to happen.")
                        .padding(.bottom, 20)
                }
                VStack(alignment: .leading) {
                    Text("There are 2 solutions:")
                    Text("1) Send screenshot of this error and wait for an update with fix")
                    Text("2) Reinstall the app and start fresh")
                        .padding(.bottom, 20)
                    Text("Error: 00")
                    Text(DataProvider.shared().databaseProblemDescription)
                }
                .padding()
                
            }
            else if !didAcceptTerms || isOnboarding || (accounts.isEmpty && noAccounts) || ns.activeAccountPublicKey.isEmpty {
                Onboarding()
                    .environmentObject(ns)
                    .environmentObject(networkMonitor)
                    .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                    .onAppear {
                        if ns.activeAccountPublicKey.isEmpty {
                            isOnboarding = true
                        }
                    }
            }
            else {
                if let loggedInAccount = ns.loggedInAccount {
                    NosturRootMenu()
                        .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                            ReadOnlyAccountInformationSheet()
                                .presentationDetents([.large])
                                .environmentObject(ns)
                                .environmentObject(themes)
                        }
                        .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                        .environmentObject(ns)
                        .environmentObject(dm)
                        .environmentObject(nvm)
                        .environmentObject(networkMonitor)
                        .environmentObject(loggedInAccount)
                        .onReceive(priceLoop) { time in
//                            if (!isViewDisplayed) { return }
                            Task.detached(priority: .low) {
                                if let newPrice = await fetchBitcoinPrice() {
                                    if (newPrice != ExchangeRateModel.shared.bitcoinPrice) {
                                        ExchangeRateModel.shared.bitcoinPrice = newPrice
                                    }
                                }
                            }
                        }
                        .background(themes.theme.listBackground)
                        .environmentObject(themes)
                        .buttonStyle(NRButtonStyle(theme: themes.theme))
                        .tint(themes.theme.accent)
                        .onAppear {
                            ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
                            configureAudioSession()
                        }
                        .onChange(of: scenePhase) { newScenePhase in
                            switch newScenePhase {
                            case .active:
                                L.og.notice("scenePhase active")
                                if !IS_CATALYST {
                                    if (NRState.shared.appIsInBackground) { // if we were actually in background (from .background, not just a few seconds .inactive)
                                        ConnectionPool.shared.connectAll()
                                        sendNotification(.scenePhaseActive)
                                        lvmManager.restoreSubscriptions()
                                        nvm.restoreSubscriptions()
                                        ns.startTaskTimers()
                                    }
                                    NRState.shared.appIsInBackground = false
                                }
                                else {
                                    ConnectionPool.shared.connectAll()
                                    sendNotification(.scenePhaseActive)
                                    lvmManager.restoreSubscriptions()
                                    nvm.restoreSubscriptions()
                                    ns.startTaskTimers()
                                }
                                
                            case .background:
                                L.og.notice("scenePhase background")
                                if !IS_CATALYST {
                                    NRState.shared.appIsInBackground = true
                                    lvmManager.stopSubscriptions()
                                }
                                sendNotification(.scenePhaseBackground)
                                // 1. Clean up
                                Maintenance.dailyMaintenance(context: DataProvider.shared().viewContext) { didRun in
                                    // 2. Save
                                    DataProvider.shared().save() {
                                        // 3. If Clean up "didRun", need to preload cache again
                                        if didRun {
                                            Importer.shared.preloadExistingIdsCache()
                                        }
                                    }
                                }
                            case .inactive:
                                L.og.notice("scenePhase inactive")
//                                if IS_CATALYST {
//                                    DataProvider.shared().save()
//                                }

                            default:
                                break
                            }
                        }
                }
                else {
                    ProgressView()
                }
            }
        }
        .onAppear {
            #if DEBUG
           // openWindow(id: "debug-window")
            #endif
        }
//        .onAppear  { startNosturing(); self.isViewDisplayed = true }
        .onAppear  { startNosturing() }
//        .onDisappear { self.isViewDisplayed = false }
        .onReceive(receiveNotification(.onBoardingIsShownChanged)) { notification in
            let onBoardingIsShown = notification.object as! Bool
            if onBoardingIsShown != isOnboarding {
                isOnboarding = onBoardingIsShown
            }
        }
        .onReceive(accounts.publisher.collect(), perform: { accounts in
            if accounts.count != NRState.shared.accounts.count {
                if ns.activeAccountPublicKey.isEmpty && !isOnboarding {
                    ns.activeAccountPublicKey = accounts.last?.publicKey ?? ""
                }
                L.og.debug("loading \(accounts.count) accounts. \(ns.activeAccountPublicKey)")
                removeDuplicateAccounts()
                NRState.shared.accounts = Array(accounts)
            }
            else if NRState.shared.accounts.isEmpty && !accounts.isEmpty {
                L.og.debug("loading \(accounts.count) accounts. \(ns.activeAccountPublicKey)")
                removeDuplicateAccounts()
                NRState.shared.accounts = Array(accounts)
            }
            else if accounts.isEmpty {
                noAccounts = true
            }
        })
        
        .onReceive(relays.publisher.collect(), perform: { relays in
            if !relays.isEmpty && !didRemoveDuplicateRelays {
                removeDuplicateRelays()
            }
        })
        
        .onReceive(dmStates.publisher.collect(), perform: { dmStates in
            if dmStates.count != dm.dmStates.count {
                removeDuplicateDMStates()
                dm.dmStates = Array(dmStates)
            }
            else if dm.dmStates.isEmpty && !dmStates.isEmpty {
                removeDuplicateDMStates()
                dm.dmStates = Array(dmStates)
            }
            else if dmStates.isEmpty {
                noDMStates = true
            }
        })
        .environmentObject(themes)
    }
    
    private func removeDuplicateAccounts() {
        var uniqueAccounts = Set<String>()
        let sortedAccounts = accounts.sorted { $0.mostRecentItemDate > $1.mostRecentItemDate }
        
        let duplicates = sortedAccounts
            .filter { account in
                guard let publicKey = account.publicKey_ else { return false }
                return !uniqueAccounts.insert(publicKey).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate accounts")
        duplicates.forEach({ duplicateAccount in
            // Before deleting, .union the follows to the existing account
            let existingAccount = sortedAccounts.first { existingAccount in
                return existingAccount.publicKey == duplicateAccount.publicKey
            }
            existingAccount?.followingPubkeys.formUnion(duplicateAccount.followingPubkeys)
            existingAccount?.privateFollowingPubkeys.formUnion(duplicateAccount.privateFollowingPubkeys)
            existingAccount?.followingHashtags.formUnion(duplicateAccount.followingHashtags)
            DataProvider.shared().viewContext.delete(duplicateAccount)
        })
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
    }
    
    private func removeDuplicateDMStates() {
        var uniqueDMStates = Set<String>()
        let sortedDMStates = dmStates.sorted { ($0.markedReadAt_ ?? .distantPast) > ($1.markedReadAt_ ?? .distantPast) }
        
        let duplicates = sortedDMStates
            .filter { dmState in
                guard dmState.contactPubkey_ != nil else { return false }
                guard dmState.accountPubkey_ != nil else { return false }
                return !uniqueDMStates.insert(dmState.conversionId).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate DM conversation states")
        duplicates.forEach({ duplicateDMState in
            DataProvider.shared().viewContext.delete(duplicateDMState)
        })
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
    }
    
    private func removeDuplicateRelays() {
        guard !didRemoveDuplicateRelays else { return }
        var uniqueRelays = Set<String>()
        let sortedRelays = relays.sorted { $0.updatedAt > $1.updatedAt }
        
        let duplicates = sortedRelays
            .filter { relay in
                guard let url = relay.url_ else { return false }
                let normalizedUrl = normalizeRelayUrl(url)
                return !uniqueRelays.insert(normalizedUrl).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate relays")
        duplicates.forEach({ duplicateRelay in
            DataProvider.shared().viewContext.delete(duplicateRelay)
        })
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
    }
    
    private func startNosturing() {
        UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
        let viewContext = DataProvider.shared().container.viewContext
        // Daily cleanup.
        if (firstTimeCompleted) {
            Maintenance.upgradeDatabase(context: viewContext)
        }
        Importer.shared.preloadExistingIdsCache()
        
        if (!firstTimeCompleted) {
            Maintenance.ensureBootstrapRelaysExist(context: viewContext)
        }
        
        DispatchQueue.main.async {
            ns.startTaskTimers()
        }
        
        // Setup connections
        let relays:[RelayData] = CloudRelay.fetchAll(context: viewContext).map { $0.toStruct() }
        
        for relay in relays {
            _ = ConnectionPool.shared.addConnection(relay)
        }
        ConnectionPool.shared.connectAll()
        
        let ss = SettingsStore.shared
        if !ss.activeNWCconnectionId.isEmpty, let nwc = NWCConnection.fetchConnection(ss.activeNWCconnectionId, context: DataProvider.shared().viewContext) {
            let addedConnection = ConnectionPool.shared.addNWCConnection(connectionId: nwc.connectionId, url: nwc.relay)
            addedConnection.connect()
            bg().perform {
                if let nwcConnection = NWCConnection.fetchConnection(ss.activeNWCconnectionId, context: bg()) {
                    NWCRequestQueue.shared.nwcConnection = nwcConnection
                    Importer.shared.nwcConnection = nwcConnection
                }
            }
        }
        
        if (!firstTimeCompleted) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                _ = GuestAccountManager.shared.createGuestAccount()
                do {
                    try NewOnboardingTracker.shared.start(pubkey: GUEST_ACCOUNT_PUBKEY)
                }
                catch {
                    L.og.error("🔴🔴✈️✈️✈️ ONBOARDING ERROR")
                }
            }
        }
        if (ns.rawExplorePubkeys.isEmpty) {
            // Fetch updated contactlist for Explore feed
            
            // First get from cache
            bg().perform {
                let r = Event.fetchRequest()
                r.predicate = NSPredicate(format: "kind == 3 && pubkey == %@", EXPLORER_PUBKEY)
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                if let exploreContactList = try? bg().fetch(r).first {
                    ns.rawExplorePubkeys = Set(exploreContactList.pTags())
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                req(RM.getAuthorContactsList(pubkey: EXPLORER_PUBKEY))
            }
        }
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            L.og.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}
