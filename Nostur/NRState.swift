//
//  NRState.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/09/2023.
//

import SwiftUI
import Combine

class NRState: ObservableObject {
    
    public var appIsInBackground = false
    
    public var resumeFeedsSubject = PassthroughSubject<Void, Never>()
    public func resumeFeeds() {
        resumeFeedsSubject.send()
    }
    
    public var pauseFeedsSubject = PassthroughSubject<Void, Never>()
    public func pauseFeeds() {
        pauseFeedsSubject.send()
    }
    
    public var draft: String {
        get { UserDefaults.standard.string(forKey: "simple_draft") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "simple_draft") }
    }
    public var restoreDraft: String {
        get { UserDefaults.standard.string(forKey: "undo_send_restore_draft") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "undo_send_restore_draft") }
    }
    
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    public static let shared = NRState()
    
    // view context
    public var accounts: [CloudAccount] = []
    
    @Published public var loggedInAccount: LoggedInAccount? = nil {
        didSet {
            loggedInAccount?.account.lastLoginAt = .now
        }
    }
    public var wot:WebOfTrust
    public var nsecBunker:NSecBunkerManager
    
    @Published var onBoardingIsShown = false {
        didSet {
            sendNotification(.onBoardingIsShownChanged, onBoardingIsShown)
        }
    }
    @Published var readOnlyAccountSheetShown:Bool = false
    var rawExplorePubkeys: Set<String> = []
    
    @MainActor public func logout(_ account: CloudAccount) {
        DataProvider.shared().viewContext.delete(account)
        DataProvider.shared().save()
    }
    
    @MainActor public func changeAccount(_ account: CloudAccount? = nil) {
        guard let account = account else {
            self.loggedInAccount = nil
            self.activeAccountPublicKey = ""
            return
        }
        
        if account.isNC {
            self.nsecBunker.setAccount(account)
        }
        let pubkey = account.publicKey
        self.loggedInAccount = LoggedInAccount(account, completion: {
            DispatchQueue.main.async {
                sendNotification(.activeAccountChanged, account)
            }
        })
        
        guard pubkey != self.activeAccountPublicKey else { return }
        self.activeAccountPublicKey = pubkey
        if mainAccountWoTpubkey == "" {
            wot.guessMainAccount()
        }
    }
    
    // Instruments: wtf? --> 70.00 ms    2.4%    70.00 ms             NRState.activeAccountPublicKey.getter
//    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    
    public var activeAccountPublicKey: String {
        get { _activeAccountPublicKey }
        set { 
            _activeAccountPublicKey = newValue
            UserDefaults.standard.setValue(newValue, forKey: "activeAccountPublicKey")
        }
    }
    
    private var _activeAccountPublicKey: String = ""
    
    // BG high speed vars
    public var accountPubkeys: Set<String> = []
    public var fullAccountPubkeys: Set<String> = []
    public var mutedWords: [String] = [] {
        didSet {
//            sendNotification(.mutedWordsChanged, mutedWords) // TODO update listeners
        }
    }
    public var blockedPubkeys: Set<String> = []
    public var mutedRootIds: Set<String> = []
    public var blockedHashtags: Set<String> = [] // put lowercased here
    
    private init() {
        self._activeAccountPublicKey = UserDefaults.standard.string(forKey: "activeAccountPublicKey") ?? ""
        self.wot = WebOfTrust.shared
        self.nsecBunker = NSecBunkerManager.shared
        signpost(self, "LAUNCH", .begin, "Initializing Nostur App State")
        managePowerUsage()
        loadMutedWords()
        loadBlockedPubkeys()
        loadBlockedHashtags()
        loadMutedRootIds()
        dynamicFontSize()
    }
    
    func dynamicFontSize() {
        NotificationCenter.default.addObserver(self, selector: #selector(preferredContentSizeChanged(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    @objc func preferredContentSizeChanged(_ notification: Notification) {
        NRTextParser.shared.reloadHashtagIcons()
        sendNotification(.dynamicTextChanged)
    }
    
    @MainActor public func loadAccountsState() {
        self.accounts = CloudAccount.fetchAccounts(context: context())
        let accountPubkeys = Set(accounts.map { $0.publicKey })
        let fullAccountPubkeys = Set(accounts.filter { $0.isFullAccount }.map { $0.publicKey })
        bg().perform {
            self.accountPubkeys = accountPubkeys
            self.fullAccountPubkeys = fullAccountPubkeys
        }
        
        // No account selected
        if activeAccountPublicKey.isEmpty {
            self.loggedInAccount = nil
            self.onBoardingIsShown = true
            sendNotification(.clearNavigation)
            Task { @MainActor in
                self.changeAccount(nil)
            }
            return
        }
        else {
            // activeAccountPublicKey but CloudAccounts changed (deduplicated?)
            if let account = accounts.first(where: { $0.publicKey == activeAccountPublicKey }) {
                if loggedInAccount?.account != account {
                    Task { @MainActor in
                        changeAccount(account)
                    }
                }
            }
            else if let nextAccount = accounts.last { // can't find account, change to next account
                Task { @MainActor in
                    changeAccount(nextAccount)
                }
            }
            else { // we don't have any accounts
                self.loggedInAccount = nil
                self.onBoardingIsShown = true
                sendNotification(.clearNavigation)
                Task { @MainActor in
                    self.changeAccount(nil)
                }
                return
            }
        }
    }
    
    private func managePowerUsage() {
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    public func loadMutedWords() {
        let fr = MutedWords.fetchRequest()
        fr.predicate = NSPredicate(format: "enabled == true")
        guard let mutedWords = try? viewContext().fetch(fr) else { return }
        self.mutedWords = mutedWords.map { $0.words }.compactMap { $0 }.filter { $0 != "" }
    }
    
    public func loadBlockedPubkeys() {
        self.blockedPubkeys = CloudBlocked.blockedPubkeys()
    }
    
    public func loadBlockedHashtags() {
        self.blockedHashtags = CloudBlocked.blockedHashtags()
    }
    
    public func loadMutedRootIds() {
        self.mutedRootIds = CloudBlocked.mutedRootIds()
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
    
    // Other
    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
    
    let agoTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()
        .delay(for: .seconds(5), scheduler: RunLoop.main)
    
    // task timers
    private var taskTimers: [Timer] = []
    
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
}

func notMain() {
    #if DEBUG
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            fatalError("Should only be called from bg()")
        }
    #endif
}

func isFollowing(_ pubkey: String) -> Bool {
    if Thread.isMainThread {
        return NRState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
    }
    else {
        return NRState.shared.loggedInAccount?.followingPublicKeys.contains(pubkey) ?? false
    }
}

func isPrivateFollowing(_ pubkey: String) -> Bool {
    if Thread.isMainThread {
        return NRState.shared.loggedInAccount?.account.privateFollowingPubkeys.contains(pubkey) ?? false
    }
    else {
        return NRState.shared.loggedInAccount?.bgAccount?.privateFollowingPubkeys.contains(pubkey) ?? false
    }
}

func followingPFP(_ pubkey: String) -> URL? {
    NRState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL
}

func account() -> CloudAccount? {
    if Thread.isMainThread {
        NRState.shared.loggedInAccount?.account ?? (try? CloudAccount.fetchAccount(publicKey: NRState.shared.activeAccountPublicKey, context: context()))
    }
    else {
        NRState.shared.loggedInAccount?.bgAccount ?? (try? CloudAccount.fetchAccount(publicKey: NRState.shared.activeAccountPublicKey, context: context()))
    }
}

func accountCache() -> AccountCache? {
    if let accountCache = NRState.shared.loggedInAccount?.accountCache, accountCache.cacheIsReady {
        return accountCache
    }
    return nil
}



func accountData() -> AccountData? {
    guard let account = Thread.isMainThread ? NRState.shared.loggedInAccount?.account : NRState.shared.loggedInAccount?.bgAccount 
    else { return nil }
    return account.toStruct()
}

func follows() -> Set<String> {
    if Thread.isMainThread {
        NRState.shared.loggedInAccount?.viewFollowingPublicKeys ?? []
    }
    else {
        NRState.shared.loggedInAccount?.followingPublicKeys ?? []
    }
}

func blocks() -> Set<String> {
    NRState.shared.blockedPubkeys
}

func blockedHashtags() -> Set<String> {
    NRState.shared.blockedHashtags
}


func isFullAccount(_ account: CloudAccount? = nil ) -> Bool {
    if Thread.isMainThread {
        return (account ?? NRState.shared.loggedInAccount?.account)?.isFullAccount ?? false
    }
    else {
        return (account ?? NRState.shared.loggedInAccount?.bgAccount)?.isFullAccount ?? false
    }
}

func showReadOnlyMessage() {
    NRState.shared.readOnlyAccountSheetShown = true;
}

final class ExchangeRateModel: ObservableObject {
    static public var shared = ExchangeRateModel()
    @Published var bitcoinPrice:Double = 0.0
}

let APP_VERSION = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
let CI_BUILD_NUMBER = Bundle.main.infoDictionary?["CI_BUILD_NUMBER"] as? String ?? "?"
let NIP89_APP_REFERENCE = Bundle.main.infoDictionary?["NIP89_APP_REFERENCE"] as? String ?? ""
let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_IPHONE = !ProcessInfo.processInfo.isMacCatalystApp && UIDevice.current.userInterfaceIdiom == .phone
let IS_APPLE_TYRANNY = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") == "NO"
//let IS_MAC = ProcessInfo.processInfo.isiOSAppOnMac


let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"


var timeTrackers: [String: CFAbsoluteTime] = [:]

let LESS_CACHE = false // For testing, deletes all events and contacts at start up

#if targetEnvironment(simulator)
    let IS_SIMULATOR = true
#else
    let IS_SIMULATOR = false
#endif



let DISABLE_BACKGROUND_TASKS: Bool = ProcessInfo.processInfo.arguments.contains("-disableBackgroundTasks")
