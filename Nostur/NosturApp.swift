//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//
import SwiftUI
import CoreData
import Combine

infix operator ?!: LogicalConjunctionPrecedence

func ?!(lhs: Bool?, rhs: Bool) -> Bool {
    return lhs ?? false && rhs
}

@main
struct NosturApp: App {
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    @StateObject private var up:Unpublisher = .shared
//    @StateObject private var nm = NotificationsManager(bgContext:EventsProvider.shared.container.newBackgroundContext())
    @StateObject private var ns:NosturState = .shared
    @StateObject private var er:ExchangeRateModel = .shared
    @StateObject private var nav:NavigationModel = .shared
    @StateObject private var sp:SocketPool = .shared
//    @StateObject private var ds:DataStore = .shared
    @StateObject private var ss:SettingsStore = .shared
    @StateObject private var sm = SideBarModel()
    @StateObject private var tm:DetailTabsModel = .shared
    @StateObject private var nm:NotificationsManager = .shared
    
    @State var isViewDisplayed = false
    
    let runLoop = Timer.publish(every: 2, tolerance: 1, on: .main, in: .common).autoconnect()
    let priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))

    var body: some Scene {
        WindowGroup {
            Onboarding()
                .environment(\.managedObjectContext, EventsProvider.shared.container.viewContext)
                .environmentObject(ns)
                .environmentObject(er)
                .environmentObject(sp)
                .environmentObject(nav)
                .environmentObject(up)
                .environmentObject(ss)
                .environmentObject(tm)
                .environmentObject(sm)
                .environmentObject(nm)
                .onAppear {startNosturing(); self.isViewDisplayed = true }
                .onDisappear { self.isViewDisplayed = false }
                .onReceive(runLoop) { time in
                    if (!isViewDisplayed) { return }
                    Task { await Importer.shared.importEvents() }
                }
                .onReceive(priceLoop) { time in
                    if (!isViewDisplayed) { return }
                    Task {
                        if let newPrice = await fetchBitcoinPrice() {
                            if (newPrice != er.bitcoinPrice) {
//                                er.objectWillChange.send()
                                er.bitcoinPrice = newPrice
                            }
                        }
                    }
                }
//                .statusBarHidden(true)
        }
    }

    func startNosturing() {
        if (ns.account == nil && ns.accounts.count >= 1) { // NosturState will set last active account in .init, else we set here:
            ns.setAccount(account: ns.accounts.last!)
        }
        else if ns.account == nil {
            ns.onBoardingIsShown = true
            Maintenance.firstTimeStartup(context: EventsProvider.shared.container.viewContext)
        }
        
        // Daily cleanup.
        //TODO: Is fast or do in background task?
        Maintenance.maintenance(context: DataProvider.shared().container.newBackgroundContext())
//        Maintenance.maintenance(context: EventsProvider.shared.container.viewContext)
        
        // One time fix
        //        repairDb()
        //        maintenance()
        
        // Get relays from Core Data, create sockets in SocketPool and connect.
        EventsProvider.shared.container.viewContext.perform {
            do {
                // Fetch RELAYS from CORE DATA
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                let sp = SocketPool.shared
                
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = try sp.addSocket(relayId: relay.objectID, url: relay.url!, read:relay.read, write: relay.write
                    )
                }
            } catch {
                print("🔴🔴🔴 Unable to Execute Fetch Request, \(error)")
            }
            
            if (!firstTimeCompleted) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    // fetch guest account kind 0 + 3
                    print("✈️✈️✈️ ONBORADING SPEED UP, FETCHING 0 + 3")
                    let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: NosturState.GUEST_ACCOUNT_PUBKEY))
                    sp.sendMessage(message)
                }
                
                
                // fetch p's in 3
                
                // fetch following events
            }
            if (ns.rawExplorePubkeys.count == 0) {
                // Fetch updated contactlist for epxlorer feed
                
                // First get from cache
                let r = Event.fetchRequest()
                r.predicate = NSPredicate(format: "kind == 3 && pubkey == %@", NosturState.EXPLORER_PUBKEY)
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                let exploreContactList = try? EventsProvider.shared.container.viewContext.fetch(r).first
                if exploreContactList != nil {
                    ns.objectWillChange.send()
                    ns.rawExplorePubkeys = Set(exploreContactList!.pTags())
                    
                }
                
                // But connect also and get newest
                SocketPool.shared.connectAll()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let message = ClientMessage(type: .REQ, message: RequestMessage.getAuthorContactsList(pubkey: NosturState.EXPLORER_PUBKEY))
                    SocketPool.shared.sendMessage(message)
                }
            }
        }
    }
}

