//
//  NRState.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/09/2023.
//

import SwiftUI

class NRState: ObservableObject {
    
    @MainActor public static let shared = NRState()
    
    // view context
    @Published public var accounts:[Account] = [] {
        didSet {
            let accountPubkeys = Set(accounts.map { $0.publicKey })
            let fullAccountPubkeys = Set(accounts.filter { $0.privateKey != nil }.map { $0.publicKey })
            bg().perform {
                self.accountPubkeys = accountPubkeys
                self.fullAccountPubkeys = fullAccountPubkeys
            }
        }
    }

    @Published public var loggedInAccount:LoggedInAccount? = nil
    public var wot:WebOfTrust
    public var nsecBunker:NSecBunkerManager
    
    @Published var onBoardingIsShown = false {
        didSet {
            sendNotification(.onBoardingIsShownChanged, onBoardingIsShown)
        }
    }
    @Published var readOnlyAccountSheetShown:Bool = false
    var rawExplorePubkeys:Set<String> = []
    
    @MainActor public func logout(_ account:Account) {
        bg().perform {
            if (account.privateKey != nil) {
                if account.isNC {
                    NIP46SecretManager.shared.deleteSecret(account: account)
                }
                else {
                    AccountManager.shared.deletePrivateKey(forPublicKeyHex: account.publicKey)
                }
            }
            bg().delete(account)
            self.loadAccounts() { accounts in
                guard let nextAccount = accounts.last else {
                    DispatchQueue.main.async {
                        sendNotification(.clearNavigation)
                        self.activeAccountPublicKey = ""
                        self.onBoardingIsShown = true
                        self.loggedInAccount = nil
                    }
                    DataProvider.shared().bgSave()
                    return
                }
                
                self.loadAccount(nextAccount)
                DataProvider.shared().bgSave()
            }
        }
    }
    
    @MainActor public func changeAccount(_ account:Account? = nil) {
        guard let account = account else {
            self.loggedInAccount = nil
            self.activeAccountPublicKey = ""
            return
        }
        bg().perform {
            guard let account = DataProvider.shared().viewContext.object(with: account.objectID) as? Account
            else {
                return
            }
            
            self.nsecBunker.setAccount(account)
            let pubkey = account.publicKey
            self.loggedInAccount = LoggedInAccount(account)
            
            DispatchQueue.main.async {
                guard pubkey != self.activeAccountPublicKey else { return }
                self.activeAccountPublicKey = pubkey
            }
        }
    }
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    
    // BG high speed vars
    private var accountPubkeys:Set<String> = []
    private var fullAccountPubkeys:Set<String> = []
    private var mutedWords:[String] = [] {
        didSet {
//            sendNotification(.mutedWordsChanged, mutedWords) // TODO update listeners
        }
    }
    
    @MainActor private init() {
        self.wot = WebOfTrust.shared
        self.nsecBunker = NSecBunkerManager.shared
        let activeAccountPublicKey = activeAccountPublicKey
        loadAccounts() { accounts in
            guard !activeAccountPublicKey.isEmpty,
                    let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: bg())
            else { return }
            self.loadAccount(account)
        }
        managePowerUsage()
        loadMutedWords()
    }
    
    @MainActor public func loadAccounts(onComplete: (([Account]) -> Void)? = nil) { // main context
        let r = Account.fetchRequest()
        guard let accounts = try? DataProvider.shared().viewContext.fetch(r) else { return }
        self.accounts = accounts
        onComplete?(accounts)
    }
    
    private func loadAccount(_ account:Account) { // main context
        self.nsecBunker.setAccount(account)
        let pubkey = account.publicKey
        self.loggedInAccount = LoggedInAccount(account)
        guard pubkey != self.activeAccountPublicKey else { return }
        self.activeAccountPublicKey = pubkey
    }
    
    private func managePowerUsage() {
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    private func loadMutedWords() {
        bg().perform {
            let fr = MutedWords.fetchRequest()
            fr.predicate = NSPredicate(format: "enabled == true")
            guard let mutedWords = try? bg().fetch(fr) else { return }
            self.mutedWords = mutedWords.map { $0.words }.compactMap { $0 }.filter { $0 != "" }
        }
    }
    
    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            if SettingsStore.shared.animatedPFPenabled {
                SettingsStore.shared.objectWillChange.send() // This will reload views to stop playing animated PFP GIFs
            }
        }
    }
    
    // Other
    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
    
    let agoTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()
}

func notMain() {
    #if DEBUG
    if Thread.isMainThread {
        fatalError("Should not be main")
    }
    #endif
}


func follows() -> Set<String> {
    NRState.shared.loggedInAccount?.viewFollowingPublicKeys ?? []
}
