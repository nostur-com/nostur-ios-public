//
//  AppState.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    
    static let shared = AppState()
    private init() {
        if UserDefaults.standard.bool(forKey: "firstTimeCompleted") {
            finishedTasks.insert(.firstTimeCopleted)
        }
        managePowerUsage()
        loadMutedWords()
        loadBlockedPubkeys()
        loadBlockedHashtags()
        loadMutedRootIds()
        handleDynamicFontSize()
        initializeAgoUpdater()
        if IS_CATALYST {
            handleAwakeFromSleep()
        }
    }
    
    // Published / Observed stuff
    @Published var finishedTasks: Set<AppTask> = []
    
    // main stuff
    public var appIsInBackground = false
    public var rawExplorePubkeys: Set<String> = []
    
    // bg stuff
    public var bgAppState = BgAppState()
    
    // local feed states
    public var localFeedStatesManager: LocalFeedStateManager = .shared
    
    // Timers
    public let minuteTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()
        .delay(for: .seconds(5), scheduler: RunLoop.main)
    
    public let agoShouldUpdateSubject = PassthroughSubject<Void, Never>()
    private var subscriptions: Set<AnyCancellable> = []
    
    private func initializeAgoUpdater() {
        minuteTimer
            .sink(receiveValue: { _ in
                self.agoShouldUpdateSubject.send()
            })
            .store(in: &subscriptions)
    }
    
    private var taskTimers: [Timer] = []
    
    // Block timers
    @MainActor
    public func startTaskTimers() {
        // We (re)create all timers, so invalidate and remove any existing
        for timer in taskTimers {
            timer.invalidate()
        }
        taskTimers = []
        
        // Get all tasks of type .blockUntil
        let tasks = CloudTask.fetchAll(byType: .blockUntil)
        guard !tasks.isEmpty else { return }
        
        // flag to track if we deleted any because its timer has already expired
        var didRemoveBlockUntilTask = false
        
        for task in tasks {
            if .now >= task.date { // if the task has already expired we remove the task from database
                // fetch the related block we need to remove also
                if let block = CloudBlocked.fetchBlock(byPubkey: task.value) {
                    context().delete(block)
                    didRemoveBlockUntilTask = true
                }
                // remove the task
                context().delete(task)
            }
            else { // not expired, so we create the timer
                createTimer(fireDate: task.date, pubkey: task.value)
            }
        }
        
        // Send notification to update views if we deleted any blocks
        if didRemoveBlockUntilTask {
            sendNotification(.blockListUpdated, CloudBlocked.blockedPubkeys())
        }
    }
    
    @objc func timerAction(_ timer: Timer) {
        let pubkey = timer.userInfo as! String
        
        // Remove task from database
        if let task = CloudTask.fetchTask(byType: .blockUntil, andPubkey: pubkey) {
            context().delete(task)
        }
        
        // Remove related block from database
        if let block = CloudBlocked.fetchBlock(byPubkey: pubkey) {
            context().delete(block)
            
            // Update views
            sendNotification(.blockListUpdated, CloudBlocked.blockedPubkeys())
        }
        
        // Invalidate and remove the timer
        timer.invalidate()
        removeTimer(timer)
    }
    
    func createTimer(fireDate: Date, pubkey: String) {
        let timer = Timer(fireAt: fireDate, interval: 0, target: self, selector: #selector(timerAction(_:)), userInfo: pubkey, repeats: false)
        taskTimers.append(timer)
        RunLoop.main.add(timer, forMode: .common)
    }
    
    func removeTimer(_ timer: Timer) {
        if let index = taskTimers.firstIndex(where: { $0 === timer }) {
            taskTimers.remove(at: index)
        }
    }
    
    
    // App wide blocking of words, pubkeys, hashtags, threads
    
    public func loadMutedWords() {
        return // TODO: FIXME
        let fr = MutedWords.fetchRequest()
        fr.predicate = NSPredicate(format: "enabled == true")
        guard let mutedWords = try? viewContext().fetch(fr) else { return }
        self.bgAppState.mutedWords = mutedWords.map { $0.words }.compactMap { $0 }.filter { $0 != "" }
    }
    
    public func loadBlockedPubkeys() {
        self.bgAppState.blockedPubkeys = CloudBlocked.blockedPubkeys()
    }
    
    public func loadBlockedHashtags() {
        self.bgAppState.blockedHashtags = CloudBlocked.blockedHashtags()
    }
    
    public func loadMutedRootIds() {
        self.bgAppState.mutedRootIds = CloudBlocked.mutedRootIds()
    }
    
    func handleDynamicFontSize() {
        NotificationCenter.default.addObserver(self, selector: #selector(preferredContentSizeChanged(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    @objc func preferredContentSizeChanged(_ notification: Notification) {
        NRTextParser.shared.reloadHashtagIcons()
        sendNotification(.dynamicTextChanged)
    }
    
    private func managePowerUsage() {
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            if SettingsStore.shared.animatedPFPenabled {
                DispatchQueue.main.async {
                    SettingsStore.shared.objectWillChange.send() // This will reload views to stop playing animated PFP GIFs
                }
            }
        }
    }
    
    private func handleAwakeFromSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, ConnectionPool.shared.connectedCount == 0 else { return }
                
                if (!self.firstWakeSkipped) {
                    self.firstWakeSkipped = true
                    return
                }
                self.handleWake()
            }
        }
    }
    
    private var firstWakeSkipped = false
    
    private func handleWake() {
        guard ConnectionPool.shared.connectedCount == 0 else { return }
        
        // Should force reconnect (reset exp backoff), wait 5 sec for device wifi / network
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            guard ConnectionPool.shared.connectedCount == 0 else { return }
            ConnectionPool.shared.connectAll(resetExpBackOff: true)
        }
        
        // Retry a bit later also
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            guard ConnectionPool.shared.connectedCount == 0 else { return }
            ConnectionPool.shared.connectAll(resetExpBackOff: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
}

extension AppState {
    enum AppTask: Hashable {
        case firstTimeCopleted
        case didRunConnectAll
    }
}


class BgAppState: ObservableObject {
    public var blockedPubkeys: Set<String> = []
    public var mutedRootIds: Set<String> = []
    public var blockedHashtags: Set<String> = [] // put lowercased here
    public var mutedWords: [String] = []
}


func blocks() -> Set<String> {
    AppState.shared.bgAppState.blockedPubkeys
}

func blockedHashtags() -> Set<String> {
    AppState.shared.bgAppState.blockedHashtags
}

func setFirstTimeCompleted() {
    if !UserDefaults.standard.bool(forKey: "firstTimeCompleted") {
        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
        }
    }
}


func startNosturing() async {
    UserDefaults.standard.register(defaults: ["selected_subtab" : "Following"])
    
#if DEBUG
    if LESS_CACHE && IS_SIMULATOR {
        LocalFeedStateManager.shared.wipeMemory()
        
        // To test if things are properly fetched and not broken if not already cached from before
        await Maintenance.deleteAllEventsAndContacts(context: bg())
    }
#endif
    
    if (AppState.shared.finishedTasks.contains(.firstTimeCopleted)) {
        await Maintenance.upgradeDatabase(context: bg())
    }
    else {
        await Maintenance.ensureBootstrapRelaysExist(context: bg())
    }
    
    await Importer.shared.preloadExistingIdsCache() // 43 MB -> 103-132 MB (but if bg is child of store instead of viewContext: 74 MB)

    await AppState.shared.startTaskTimers()
    
    await setupConnections()
    AppState.shared.finishedTasks.insert(.didRunConnectAll)
    
    Task {
        async let nwcTask: () = initializeNWCConnection()
        async let exploreTask: () = initializeExplore()
        async let guestAccountTask: () = initializeGuestAccount()
        let _ = await [nwcTask, exploreTask, guestAccountTask]
    }
}

func setupConnections() async {
#if DEBUG
    L.og.debug("🚀🚀 Setting up connections")
#endif
    let relays: [RelayData] = await bg().perform {
        return CloudRelay.fetchAll(context: bg()).map { $0.toStruct() }
    }
    
    for relay in relays {
        ConnectionPool.shared.addConnection(relay)
    }
    
    ConnectionPool.shared.connectAll()
}

func initializeExplore() async {
#if DEBUG
    L.og.debug("🚀🚀 Setting up Explore")
#endif
    if (AppState.shared.rawExplorePubkeys.isEmpty) {
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
        AppState.shared.rawExplorePubkeys = rawExplorePubkeys
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            req(RM.getAuthorContactsList(pubkey: EXPLORER_PUBKEY))
        }
    }
}

func initializeGuestAccount() async {
#if DEBUG
        L.og.debug("🚀🚀 Setting up Guest account")
#endif
    if (!AppState.shared.finishedTasks.contains(.firstTimeCopleted)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            bg().perform {
                _ = GuestAccountManager.shared.createGuestAccount()
                DataProvider.shared().saveToDiskNow()
                do {
                    try NewOnboardingTracker.shared.start(pubkey: GUEST_ACCOUNT_PUBKEY)
                }
                catch {
                    L.og.error("🔴🔴✈️✈️✈️ ONBOARDING ERROR")
                }
            }
        }
    }
}

func initializeNWCConnection() async {
#if DEBUG
    L.og.debug("🚀🚀 Setting up NWC Connection")
#endif
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
}


let APP_VERSION = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
let CI_BUILD_NUMBER = Bundle.main.infoDictionary?["CI_BUILD_NUMBER"] as? String ?? "?"
let NIP89_APP_NAME = Bundle.main.infoDictionary?["NIP89_APP_NAME"] as? String ?? "Nostur"
let NIP89_APP_REFERENCE = Bundle.main.infoDictionary?["NIP89_APP_REFERENCE"] as? String ?? ""
let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_IPHONE = !ProcessInfo.processInfo.isMacCatalystApp && UIDevice.current.userInterfaceIdiom == .phone
func IS_DESKTOP_COLUMNS() -> Bool {
    IS_CATALYST && SettingsStore.shared.proMode 
}

let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"
let GUEST_FOLLOWS_FALLBACK: Set<String> = ["dedf91f5c5eee3f3864eec34b28fc99c6a8cc44b250888ccf4d0d8d854f48d54",
                              "72f9755501e1a4464f7277d86120f67e7f7ec3a84ef6813cc7606bf5e0870ff3",
                              "95361a2b42a26c22bac3b6b6ba4c5cac4d36906eb0cfb98268681c45a301c518",
                              "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93",
                              "55f04590674f3648f4cdc9dc8ce32da2a282074cd0b020596ee033d12d385185",
                              "bf943b7165fca616a483c6dc701646a29689ab671110fcddba12a3a5894cda15",
                              "7f3b464b9ff3623630485060cbda3a7790131c5339a7803bde8feb79a5e1b06a",
                              "a9434ee165ed01b286becfc2771ef1705d3537d051b387288898cc00d5c885be",
                              "076161ca22da5a2ab8c74465cbf08f79f3e7e8bb31f4dc211bd94319ebade03d",
                              "090254801a7e8e5085b02e711622f0dfa1a85503493af246aa42af08f5e4d2df",
                              "1989034e56b8f606c724f45a12ce84a11841621aaf7182a1f6564380b9c4276b",
                              "4df7b43b3a4db4b99e3dbad6bd0f84226726efd63ae7e027f91acbd91b4dba48",
                              "020f2d21ae09bf35fcdfb65decf1478b846f5f728ab30c5eaabcd6d081a81c3e",
                              "4523be58d395b1b196a9b8c82b038b6895cb02b683d0c253a955068dba1facd0",
                              "234c45ff85a31c19bf7108a747fa7be9cd4af95c7d621e07080ca2d663bb47d2",
                              "c7d32972e398d4d20cd69b1a8451956cc14a2e9065ad1a8fda185c202698937b",
                              "19fefd7f39c96d2ff76f87f7627ae79145bc971d8ab23205005939a5a913bc2f",
                              "58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196",
                              "c47daa0cd21a70797fe9404f8fe0c3f679c2b46148788d1295e6424232064f1d",
                              "c230edd34ca5c8318bf4592ac056cde37519d395c0904c37ea1c650b8ad4a712",
                              "7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194",
                              "62fe02416353e9ac019c21f99b8288f53d1d29ea2d860653a67690d747d6e4ec",
                              "a4cb51f4618cfcd16b2d3171c466179bed8e197c43b8598823b04de266cef110",
                              "b99dbca0184a32ce55904cb267b22e434823c97f418f36daf5d2dff0dd7b5c27",
                              "11b9a89404dbf3034e7e1886ba9dc4c6d376f239a118271bd2ec567a889850ce",
                              "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240",
                              "c7dccba4fe4426a7b1ea239a5637ba40fab9862c8c86b3330fe65e9f667435f6",
                              "9ce71f1506ccf4b99f234af49bd6202be883a80f95a155c6e9a1c36fd7e780c7",
                              "a341f45ff9758f570a21b000c17d4e53a3a497c8397f26c0e6d61e5acffc7a98",
                              "74ffc51cc30150cf79b6cb316d3a15cf332ab29a38fec9eb484ab1551d6d1856",
                              "c9b19ffcd43e6a5f23b3d27106ce19e4ad2df89ba1031dd4617f1b591e108965",
                              "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
                              "3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd",
                              "bf2376e17ba4ec269d10fcc996a4746b451152be9031fa48e74553dde5526bce",
                              "d987084c48390a290f5d2a34603ae64f55137d9b4affced8c0eae030eb222a25",
                              "387519cafd325668ecffe59577f37238638da4cf2d985b82f932fc81d33da1e8",
                              "eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f",
                              "883fea4c071fda4406d2b66be21cb1edaf45a3e058050d6201ecf1d3596bbc39",
                              "7b3f7803750746f455413a221f80965eecb69ef308f2ead1da89cc2c8912e968",
                              "3d2e51508699f98f0f2bdbe7a45b673c687fe6420f466dc296d90b908d51d594",
                              "266815e0c9210dfa324c6cba3573b14bee49da4209a9456f9484e5106cd408a5",
                              "064de2497ce621aee2a5b4b926a08b1ca01bce9da85b0c714e883e119375140c",
                              "edcd20558f17d99327d841e4582f9b006331ac4010806efa020ef0d40078e6da",
                              "c2622c916d9b90e10a81b2ba67b19bdfc5d6be26c25756d1f990d3785ce1361b",
                              "27f211f4542fd89d673cfad15b6d838cc5d525615aae8695ed1dcebc39b2dadb",
                              "0a722ca20e1ccff0adfdc8c2abb097957f0e0bf32db18c4281f031756d50eb8d",
                              "1b11ed41e815234599a52050a6a40c79bdd3bfa3d65e5d4a2c8d626698835d6d",
                              "5a8e581f16a012e24d2a640152ad562058cb065e1df28e907c1bfa82c150c8ba",
                              "826e9f895b81ab41a4522268b249e68d02ca81608def562a493cee35ffc5c759",
                              "296842eaaed9be5ae0668da09fe48aac0521c4af859ad547d93145e5ac34c17e",
                              "e1ff3bfdd4e40315959b08b4fcc8245eaa514637e1d4ec2ae166b743341be1af",
                              "83e818dfbeccea56b0f551576b3fd39a7a50e1d8159343500368fa085ccd964b",
                              "e9e4276490374a0daf7759fd5f475deff6ffb9b0fc5fa98c902b5f4b2fe3bba2",
                              "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9",
                              "bc385dfbeaa4131fefb92f84a9c50e4bc4260e2da5183f7113aecd5f1d301abf",
                              "b0b8fbd9578ac23e782d97a32b7b3a72cda0760761359bd65661d42752b4090a",
                              "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245",
                              "6e1534f56fc9e937e06237c8ba4b5662bcacc4e1a3cfab9c16d89390bec4fca3",
                              "b8e6bf46e109314616fe24e6c7e265791a5f2f4ec95ae8aa15d7107ad250dc63",
                              "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
                              "eaf27aa104833bcd16f671488b01d65f6da30163b5848aea99677cc947dd00aa",
                              "76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa",
                              "c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0",
                              "8766a54ef9a170b3860bc66fd655abb24b5fda75d7d7ff362f44442fbdeb47b9",
                              "aef0d6b212827f3ba1de6189613e6d4824f181f567b1205273c16895fdaf0b23",
                              "f728d9e6e7048358e70930f5ca64b097770d989ccd86854fe618eda9c8a38106",
                              "fdd5e8f6ae0db817be0b71da20498c1806968d8a6459559c249f322fa73464a7",
                              "3743244390be53473a7e3b3b8d04dce83f6c9514b81a997fb3b123c072ef9f78",
                              "29fbc05acee671fb579182ca33b0e41b455bb1f9564b90a3d8f2f39dee3f2779",
                              "6c237d8b3b120251c38c230c06d9e48f0d3017657c5b65c8c36112eb15c52aeb",
                              "b9003833fabff271d0782e030be61b7ec38ce7d45a1b9a869fbdb34b9e2d2000",
                              "9579444852221038dcba34512257b66a1c6e5bdb4339b6794826d4024b3e4ce9",
                              "6f35047caf7432fc0ab54a28fed6c82e7b58230bf98302bf18350ff71e10430a",
                              "f5fd754857046f37eae58c982d7a0991ba08c996f5b3390fa2bad47ef2718ded",
                              "50a25300cc08675d90d834475405a7f16668c0f2f1c2238b2ce9fc43d13b6646",
                              "50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63",
                              "3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
                              "be1d89794bf92de5dd64c1e60f6a2c70c140abac9932418fee30c5c637fe9479",
                              "472f440f29ef996e92a186b8d320ff180c855903882e59d50de1b8bd5669301e",
                              "d8bcfacfcd875d196251b0e9fcd6932f960e22e45d3e6cc48c898917aa97645b",
                              "8fe3f243e91121818107875d51bca4f3fcf543437aa9715150ec8036358939c5",
                              "ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc",
                              "c48e29f04b482cc01ca1f9ef8c86ef8318c059e0e9353235162f080f26e14c11",
                              "8771794f986b6572683b1b7499b2e3de4b38e9f83501b5afaf03cc597ceba55e",
                              "e88a691e98d9987c964521dff60025f60700378a4879180dcbbb4a5027850411",
                              "c49d52a573366792b9a6e4851587c28042fb24fa5625c6d67b8c95c8751aca15",
                              "d26f78e5954117b5c6538a2d6c88a2296c65c038770399d7069a97826eb06a95"]


let LESS_CACHE = false // For testing, deletes all events and contacts at start up + wipe feed states

#if targetEnvironment(simulator)
    let IS_SIMULATOR = true
#else
    let IS_SIMULATOR = false
#endif

let AVAILABLE_26 = if #available(iOS 26.0, *) { true } else { false }
let AVAILABLE_18 = if #available(iOS 18.0, *) { true } else { false }
let AVAILABLE_17 = if #available(iOS 17.0, *) { true } else { false }
let AVAILABLE_16 = if #available(iOS 16.0, *) { true } else { false }
