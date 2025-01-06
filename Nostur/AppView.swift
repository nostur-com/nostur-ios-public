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
import NavigationBackport

/// The main app view
///
/// Shows one of 3: Onboarding, Main app screen, or Critical database failure preventing the app from loading further
struct AppView: View {  
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var ns:NRState
    @EnvironmentObject private var networkMonitor:NetworkMonitor
    @EnvironmentObject private var dm:DirectMessageViewModel
    
    @Environment(\.scenePhase) private var scenePhase
    // These singletons always exists during the apps lifetime
    @State private var er:ExchangeRateModel = .shared
    @State private var eventRelationsQueue:EventRelationsQueue = .shared
//    @State private var lvmManager:LVMManager = .shared
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
    @State private var sound:SoundManager = .shared
    @State private var textParser:NRTextParser = .shared
    
    @AppStorage("firstTimeCompleted") private var firstTimeCompleted = false
    @AppStorage("did_accept_terms") private var didAcceptTerms = false
    
    
//    @State private var isViewDisplayed = false
    @State private var isOnboarding = false
    
    @State private var priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))

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
            else {
                if !didAcceptTerms || isOnboarding || (didLoad && ns.accounts.isEmpty) || ns.activeAccountPublicKey.isEmpty {
                    NBNavigationStack {
                        Onboarding()
                            .withNavigationDestinations() // TODO maybe make seperate for just onboarding
                            .environmentObject(themes)
                            .environmentObject(ns)
                            .environmentObject(networkMonitor)
                            .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                            .onAppear {
                                if ns.activeAccountPublicKey.isEmpty {
                                    isOnboarding = true
                                }
                            }
                    }
                    .nbUseNavigationStack(.never)
                }
                else {
                    if let loggedInAccount = ns.loggedInAccount { // 74 MB -> 175MB
                        NosturRootMenu()
                            .environmentObject(themes)
                            .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                                NBNavigationStack {
                                    ReadOnlyAccountInformationSheet()
                                        .presentationDetentsLarge()
                                        .environmentObject(ns)
                                        .environmentObject(themes)
                                }
                                .nbUseNavigationStack(.never)
                            }
                            .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                            .environmentObject(ns)
    //                        .environmentObject(dm)
                            .environmentObject(NotificationsViewModel.shared)
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
//                                .environmentObject(themes)
    //                        .buttonStyle(NRButtonStyle(theme: themes.theme)) // This breaks .swipeActions in Lists - WTF?
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
                                            NRState.shared.resumeFeeds()
                                            NotificationsViewModel.shared.restoreSubscriptions()
                                            ns.startTaskTimers()
                                        }
                                        NRState.shared.appIsInBackground = false
                                    }
                                    else {
                                        ConnectionPool.shared.connectAll()
                                        sendNotification(.scenePhaseActive)
                                        NRState.shared.resumeFeeds()
                                        NotificationsViewModel.shared.restoreSubscriptions()
                                        ns.startTaskTimers()
                                    }
                                    
                                case .background:
                                    L.og.notice("scenePhase background")
                                    if !IS_CATALYST {
                                        NRState.shared.appIsInBackground = true
                                        NRState.shared.pauseFeeds()
                                    }
                                    sendNotification(.scenePhaseBackground)
                                    
                                    let lastMaintenanceTimestamp = Date(timeIntervalSince1970: TimeInterval(SettingsStore.shared.lastMaintenanceTimestamp))
                                    let hoursAgo = Date(timeIntervalSinceNow: (-5 * 24 * 60 * 60))
                                    let runNow = lastMaintenanceTimestamp < hoursAgo
                                    
                                    if IS_CATALYST || runNow { // macOS doesn't do background processing tasks, so we do it here instead of .scheduleDatabaseCleaningIfNeeded(). OR we do it if for whatever reason iOS has not run it for 5 days in background the processing task
                                        // 1. Clean up
                                        Task {
                                            let didRun = await Maintenance.dailyMaintenance(context: bg())
                                            if didRun {
                                                await Importer.shared.preloadExistingIdsCache()
                                            }
                                            else {
                                                viewContextSave() // need to save to sync cloud for feed.lastRead
                                            }
                                        }
                                    }
                                    else {
                                        viewContextSave() // need to save to sync cloud for feed.lastRead
                                    }
                                case .inactive:
                                    L.og.notice("scenePhase inactive")
                                    
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
        }
        .task {
            await startNosturing()
        }
        .onReceive(receiveNotification(.onBoardingIsShownChanged)) { notification in
            let onBoardingIsShown = notification.object as! Bool
            if onBoardingIsShown != isOnboarding {
                isOnboarding = onBoardingIsShown
            }
        }
    }
    
    private func startNosturing() async {
        UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
        
        if (firstTimeCompleted) {
            await Maintenance.upgradeDatabase(context: bg())
        }
        else {
            await Maintenance.ensureBootstrapRelaysExist(context: bg())
        }
        
        await Importer.shared.preloadExistingIdsCache() // 43 MB -> 103-132 MB (but if bg is child of store instead of viewContext: 74 MB)

        Task {
            let relays: [RelayData] = await bg().perform {
                ns.startTaskTimers()
                
                // Setup connections
                return CloudRelay.fetchAll(context: bg()).map { $0.toStruct() }
            }
            
            for relay in relays {
                ConnectionPool.shared.addConnection(relay)
            }
            
            ConnectionPool.shared.connectAll()
            
            if !SettingsStore.shared.activeNWCconnectionId.isEmpty {
                await bg().perform {
                    if let nwc = NWCConnection.fetchConnection(SettingsStore.shared.activeNWCconnectionId, context: bg()) {
                        NWCRequestQueue.shared.nwcConnection = nwc
                        Importer.shared.nwcConnection = nwc
                        
                        ConnectionPool.shared.addNWCConnection(connectionId: nwc.connectionId, url: nwc.relay) { conn in
                            conn.connect()
                        }
                    }
                }
            }
            
            Task {
                if (ns.rawExplorePubkeys.isEmpty) {
                    // Fetch updated contactlist for Explore feed
        
                    // First get from cache
                    let rawExplorePubkeys = await bg().perform {
                        let r = Event.fetchRequest()
                        r.predicate = NSPredicate(format: "kind == 3 && pubkey == %@", EXPLORER_PUBKEY)
                        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                        if let exploreContactList = try? bg().fetch(r).first {
                            return Set(exploreContactList.pTags())
                        }
                        return Set()
                    }
                    ns.rawExplorePubkeys = rawExplorePubkeys
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        req(RM.getAuthorContactsList(pubkey: EXPLORER_PUBKEY))
                    }
                }
                
                if (!firstTimeCompleted) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        bg().perform {
                            _ = GuestAccountManager.shared.createGuestAccount()
                            DataProvider.shared().save()
                            do {
                                try NewOnboardingTracker.shared.start(pubkey: GUEST_ACCOUNT_PUBKEY)
                            }
                            catch {
                                L.og.error("🔴🔴✈️✈️✈️ ONBOARDING ERROR")
                            }
                        }
                    }
                }
                
                loadAccounts()
            }
        }
        return

    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            L.og.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    @State private var didLoad = false
    private func loadAccounts() {
        NRState.shared.loadAccountsState()
        didLoad = true
    }
}
