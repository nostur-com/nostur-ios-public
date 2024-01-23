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
    
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var sound:SoundManager = .shared
    
//    @EnvironmentObject private var themes:Themes
    @AppStorage("firstTimeCompleted") private var firstTimeCompleted = false
    @AppStorage("did_accept_terms") private var didAcceptTerms = false
    
    
//    @State private var isViewDisplayed = false
    @State private var isOnboarding = false
    
    @State private var priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))
    
    @StateObject private var themes:Themes = .default

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
                    Onboarding()
                        .nbUseNavigationStack(.never)
                        .environmentObject(ns)
                        .environmentObject(networkMonitor)
                        .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                        .onAppear {
                            if ns.activeAccountPublicKey.isEmpty {
                                isOnboarding = true
                            }
                        }
                }
//                    else if (1 == 1) {
//                        Text("test")
//                            .onReceive(ViewUpdates.shared.bookmarkUpdates.receive(on: RunLoop.main), perform: { update in
////                                    let update = update as! BookmarkUpdate
////                                    guard eventModel.isRelevantUpdate(update) else { return }
////                                    eventModel.applyUpdate(update)
//
//                                print("new update: \(update.id) isBookmarked: \(update.isBookmarked)")
//                                bg().perform {
//                                    try? bg().save()
//                                }
//                            })
//                    }
                else {
                    if let loggedInAccount = ns.loggedInAccount { // 74 MB -> 175MB
                        NosturRootMenu()
                            .nbUseNavigationStack(.never)
                            .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                                ReadOnlyAccountInformationSheet()
                                    .presentationDetentsLarge()
                                    .environmentObject(ns)
                                    .environmentObject(themes)
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
                            .environmentObject(themes)
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
                                            lvmManager.restoreSubscriptions()
                                            NotificationsViewModel.shared.restoreSubscriptions()
                                            ns.startTaskTimers()
                                        }
                                        NRState.shared.appIsInBackground = false
                                    }
                                    else {
                                        ConnectionPool.shared.connectAll()
                                        sendNotification(.scenePhaseActive)
                                        lvmManager.restoreSubscriptions()
                                        NotificationsViewModel.shared.restoreSubscriptions()
                                        ns.startTaskTimers()
                                    }
                                    
                                case .background:
                                    L.og.notice("scenePhase background")
                                    if !IS_CATALYST {
                                        NRState.shared.appIsInBackground = true
                                        lvmManager.stopSubscriptions()
                                    }
                                    sendNotification(.scenePhaseBackground)
                                    
                                    if IS_CATALYST { // macOS doesn't do background processing tasks, so we do it here instead of .scheduleDatabaseCleaningIfNeeded()
                                        // 1. Clean up
                                        Task {
                                            let didRun = await Maintenance.dailyMaintenance(context: bg())
                                            if didRun {
                                                await Importer.shared.preloadExistingIdsCache()
                                            }
                                        }
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
        .environmentObject(themes)
    }
    
    private func startNosturing() async {
        UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
        
        if (firstTimeCompleted) {
            await Maintenance.upgradeDatabase(context: bg())
        }
        else {
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
        
        await Maintenance.ensureBootstrapRelaysExist(context: bg())
        
        await Importer.shared.preloadExistingIdsCache() // 43 MB -> 103-132 MB (but if bg is child of store instead of viewContext: 74 MB)

        Task {
            let relays: [RelayData] = await bg().perform {
                ns.startTaskTimers()
                
                // Setup connections
                return CloudRelay.fetchAll(context: bg()).map { $0.toStruct() }
            }
            
            for relay in relays {
                _ = ConnectionPool.shared.addConnection(relay)
            }
            
            ConnectionPool.shared.connectAll()
            
            Task {
                let addedConnection: RelayConnection? = await bg().perform {
                    if !SettingsStore.shared.activeNWCconnectionId.isEmpty,
                        let nwc = NWCConnection.fetchConnection(SettingsStore.shared.activeNWCconnectionId, context: bg()) {
                        
                        NWCRequestQueue.shared.nwcConnection = nwc
                        Importer.shared.nwcConnection = nwc
                        
                        return ConnectionPool.shared.addNWCConnection(connectionId: nwc.connectionId, url: nwc.relay)
                    }
                    return nil
                }
                addedConnection?.connect()
                
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
                    loadAccounts()
                }
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
