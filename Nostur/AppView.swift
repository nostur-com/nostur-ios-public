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
    @Environment(\.scenePhase) private var scenePhase
    
    // These singletons always exists during the apps lifetime
    @State private var tm:DetailTabsModel = .shared
    @State private var er:ExchangeRateModel = .shared
    @State private var dataProvider = DataProvider.shared()
    @State private var eventRelationsQueue:EventRelationsQueue = .shared
    @State private var lvmManager:LVMManager = .shared
    @State private var importer:Importer = .shared
    @State private var queuedFetcher:QueuedFetcher = .shared
    @State private var sp:SocketPool = .shared
    @State private var esp:EphemeralSocketPool = .shared
    @State private var mp:MessageParser = .shared
    @State private var zpvq:ZapperPubkeyVerificationQueue = .shared
    @State private var nip05verifier:NIP05Verifier = .shared
    @State private var ip:ImageProcessing = .shared
    @State private var avcache:AVAssetCache = .shared
    @State private var idr:ImageDecoderRegistry = .shared
    @State private var nm:NotificationsViewModel = .shared
    @State private var kind0:Kind0Processor = .shared
    @State private var nwcRQ:NWCRequestQueue = .shared
    @State private var ss:SettingsStore = .shared
    @State private var dm:DirectMessageViewModel = .default
    @State private var nvm:NotificationsViewModel = .shared
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
    
    @StateObject private var ns:NRState = .shared
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
            else if !didAcceptTerms || isOnboarding || ns.accounts.isEmpty || ns.activeAccountPublicKey.isEmpty {
                Onboarding()
                    .environmentObject(ns)
                    .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                    .onAppear { isOnboarding = true }
                
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
                        .environmentObject(nm)
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
                                sendNotification(.scenePhaseActive)
                                SocketPool.shared.connectAll()
                                lvmManager.restoreSubscriptions()
                            case .background:
                                L.og.notice("scenePhase background")
                                sendNotification(.scenePhaseBackground)
                                if !IS_CATALYST {
                                    SocketPool.shared.disconnectAll()
                                    lvmManager.stopSubscriptions()
                                }
                                saveState()
                            case .inactive:
                                L.og.notice("scenePhase inactive")
                                if IS_CATALYST {
                                    saveState()
                                }

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
//        .onAppear  { startNosturing(); self.isViewDisplayed = true }
        .onAppear  { startNosturing() }
//        .onDisappear { self.isViewDisplayed = false }
        .onReceive(receiveNotification(.onBoardingIsShownChanged)) { notification in
            let onBoardingIsShown = notification.object as! Bool
            if onBoardingIsShown != isOnboarding {
                isOnboarding = onBoardingIsShown
            }
        }
        .environmentObject(themes)
    }
    
    private func startNosturing() {
        UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
        
        // Daily cleanup.
        if (firstTimeCompleted) {
            Maintenance.maintenance(context:DataProvider.shared().container.viewContext)
        }
        else {
            Importer.shared.preloadExistingIdsCache()
        }
        
        if (!firstTimeCompleted) {
            Maintenance.ensureBootstrapRelaysExist(context: DataProvider.shared().container.viewContext)
        }
        
        // Setup connections
        SocketPool.shared.setup(ss.activeNWCconnectionId)
        if !ss.activeNWCconnectionId.isEmpty {
            bg().perform {
                if let nwcConnection = NWCConnection.fetchConnection(ss.activeNWCconnectionId, context: DataProvider.shared().bg) {
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
                    L.og.error("🔴🔴✈️✈️✈️ ONBORADING ERROR")
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
    
    /// Saves state to disk
    func saveState() {
        DataProvider.shared().save()
        L.og.notice("State saved")
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}
