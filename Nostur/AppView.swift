//
//  AppView.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/05/2023.
//

import SwiftUI
import Combine

/// The main app view
///
/// Shows one of 3: Onboarding, Main app screen, or Critical database failure preventing the app from loading further
struct AppView: View {
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    @AppStorage("did_accept_terms") var didAcceptTerms = false
    private var nwcRQ:NWCRequestQueue = .shared
    let ss:SettingsStore = .shared
    @StateObject private var ns:NosturState = .shared
    
    @State var isViewDisplayed = false
    @State var isOnboarding = false
    
    let priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))
    
    var body: some View {
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
                if let account = ns.account {
                    NosturRootMenu(account: account)
                        .sheet(isPresented: $ns.readOnlyAccountSheetShown) {
                            ReadOnlyAccountInformationSheet()
                                .presentationDetents([.large])
                                .environmentObject(ns)
                        }
                        .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                        .environmentObject(ns)
                        .onReceive(priceLoop) { time in
                            if (!isViewDisplayed) { return }
                            Task.detached(priority: .low) {
                                if let newPrice = await fetchBitcoinPrice() {
                                    if (newPrice != ExchangeRateModel.shared.bitcoinPrice) {
                                        ExchangeRateModel.shared.bitcoinPrice = newPrice
                                    }
                                }
                            }
                        }
                }
                else {
                    ProgressView()
                }
            }
        }
        .onAppear  { startNosturing(); self.isViewDisplayed = true }
        .onDisappear { self.isViewDisplayed = false }
        .onReceive(receiveNotification(.onBoardingIsShownChanged)) { notification in
            let onBoardingIsShown = notification.object as! Bool
            if onBoardingIsShown != isOnboarding {
                isOnboarding = onBoardingIsShown
            }
        }
    }
    
    func startNosturing() {
        UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
        
        if (ns.account == nil && ns.accounts.count >= 1) { // NosturState will set last active account in .init, else we set here:
            ns.setAccount(account: ns.accounts.last!)
        }
        
        // Daily cleanup.
        if (firstTimeCompleted) {
            Maintenance.maintenance(context: DataProvider.shared().container.newBackgroundContext())
        }
        
        if (!firstTimeCompleted) {
            Maintenance.ensureBootstrapRelaysExist(context: DataProvider.shared().container.viewContext)
        }
        
        // Setup connections
        SocketPool.shared.setup(ss.activeNWCconnectionId)
        if !ss.activeNWCconnectionId.isEmpty {
            DataProvider.shared().bg.perform {
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
                    try NewOnboardingTracker.shared.start(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY)
                }
                catch {
                    L.og.error("🔴🔴✈️✈️✈️ ONBORADING ERROR")
                }
            }
        }
        if (ns.rawExplorePubkeys.isEmpty) {
            // Fetch updated contactlist for Explore feed
            
            // First get from cache
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "kind == 3 && pubkey == %@", NosturState.EXPLORER_PUBKEY)
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let exploreContactList = try?  DataProvider.shared().viewContext.fetch(r).first
            if exploreContactList != nil {
                ns.objectWillChange.send()
                ns.rawExplorePubkeys = Set(exploreContactList!.pTags())
                
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                req(RM.getAuthorContactsList(pubkey: NosturState.EXPLORER_PUBKEY))
            }
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}
