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
        localFeedStates = LocalFeedStates.load() ?? LocalFeedStates(localFeedStates: [])
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
    }
    
    // Published / Observed stuff
    @Published var finishedTasks: Set<AppTask> = []
    
    // main stuff
    public var appIsInBackground = false
    public var rawExplorePubkeys: Set<String> = []
    
    // bg stuff
    public var bgAppState = BgAppState()
    
    // local feed states
    public var localFeedStates: LocalFeedStates
    
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
let NIP89_APP_REFERENCE = Bundle.main.infoDictionary?["NIP89_APP_REFERENCE"] as? String ?? ""
let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_IPHONE = !ProcessInfo.processInfo.isMacCatalystApp && UIDevice.current.userInterfaceIdiom == .phone
let IS_APPLE_TYRANNY = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") == "NO"

let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"

let LESS_CACHE = false // For testing, deletes all events and contacts at start up

#if targetEnvironment(simulator)
    let IS_SIMULATOR = true
#else
    let IS_SIMULATOR = false
#endif

