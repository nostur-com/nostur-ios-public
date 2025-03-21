//
//  AccountsState.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI


class AccountsState: ObservableObject {
    
    static let shared = AccountsState()
    private init() {
        self._activeAccountPublicKey = UserDefaults.standard.string(forKey: "activeAccountPublicKey") ?? ""
    }
    
    @Published var finishedTasks: Set<AccountTask> = []
    
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    
    // view context
    public var activeAccountPublicKey: String {
        get { _activeAccountPublicKey }
        set {
            self.objectWillChange.send()
            _activeAccountPublicKey = newValue
            UserDefaults.standard.setValue(newValue, forKey: "activeAccountPublicKey")
        }
    }
    private var _activeAccountPublicKey: String
    public var accounts: [CloudAccount] = []
    
    // bgContext
    public var bgAccountPubkeys: Set<String> = []
    public var bgFullAccountPubkeys: Set<String> = []
    
    @Published public var loggedInAccount: LoggedInAccount? = nil {
        didSet {
            loggedInAccount?.account.lastLoginAt = .now
        }
    }
    
    @MainActor public func loadAccountsState() {
        self.accounts = CloudAccount.fetchAccounts(context: context())
        let accountPubkeys = Set(accounts.map { $0.publicKey })
        let fullAccountPubkeys = Set(accounts.filter { $0.isFullAccount }.map { $0.publicKey })
        bg().perform {
            self.bgAccountPubkeys = accountPubkeys
            self.bgFullAccountPubkeys = fullAccountPubkeys
        }
        
        // No account selected
        if activeAccountPublicKey.isEmpty {
            self.loggedInAccount = nil
            self.finishedTasks.removeAll()
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
                self.finishedTasks.removeAll()
                sendNotification(.clearNavigation)
                Task { @MainActor in
                    self.changeAccount(nil)
                }
                return
            }
        }
    }
    
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
            NSecBunkerManager.shared.setAccount(account)
        }
        let pubkey = account.publicKey
        self.loggedInAccount = LoggedInAccount(account, completion: {
            DispatchQueue.main.async {
                sendNotification(.activeAccountChanged, account)
            }
        })
        
        if let loggedInAccount = self.loggedInAccount {
            // TODO: timing this and sendNotification(.activeAccountChanged, account) is weird
            self.finishedTasks.insert(.accountInfoReady(loggedInAccount))
        }
        
        guard pubkey != self.activeAccountPublicKey else { return }
        self.activeAccountPublicKey = pubkey
        if mainAccountWoTpubkey == "" {
            WebOfTrust.shared.guessMainAccount()
        }
    }
}

extension AccountsState {
    enum AccountTask: Hashable {
        case followListReady // kind:3
        case accountInfoReady(LoggedInAccount) // kind:0
        case followListProfilesReady // kind:0 of Ps in kind:3
        case outboxRelaysReady // kind:10002
        case WoTready
    }
}



// Helpers

func isFollowing(_ pubkey: String) -> Bool {
    if Thread.isMainThread {
        return AccountsState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
    }
    else {
        return AccountsState.shared.loggedInAccount?.followingPublicKeys.contains(pubkey) ?? false
    }
}

func isPrivateFollowing(_ pubkey: String) -> Bool {
    if Thread.isMainThread {
        return AccountsState.shared.loggedInAccount?.account.privateFollowingPubkeys.contains(pubkey) ?? false
    }
    else {
        return AccountsState.shared.loggedInAccount?.bgAccount?.privateFollowingPubkeys.contains(pubkey) ?? false
    }
}

func followingPFP(_ pubkey: String) -> URL? {
    AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL
}

func account() -> CloudAccount? {
    if Thread.isMainThread {
        AccountsState.shared.loggedInAccount?.account ?? (try? CloudAccount.fetchAccount(publicKey: AccountsState.shared.activeAccountPublicKey, context: context()))
    }
    else {
        AccountsState.shared.loggedInAccount?.bgAccount ?? (try? CloudAccount.fetchAccount(publicKey: AccountsState.shared.activeAccountPublicKey, context: context()))
    }
}

func accountCache() -> AccountCache? {
    if let accountCache = AccountsState.shared.loggedInAccount?.accountCache, accountCache.cacheIsReady {
        return accountCache
    }
    return nil
}

func accountData() -> AccountData? {
    guard let account = Thread.isMainThread ? AccountsState.shared.loggedInAccount?.account : AccountsState.shared.loggedInAccount?.bgAccount
    else { return nil }
    return account.toStruct()
}

func follows() -> Set<String> {
    if Thread.isMainThread {
        AccountsState.shared.loggedInAccount?.viewFollowingPublicKeys ?? []
    }
    else {
        AccountsState.shared.loggedInAccount?.followingPublicKeys ?? []
    }
}

func isFullAccount(_ account: CloudAccount? = nil ) -> Bool {
    if Thread.isMainThread {
        return (account ?? AccountsState.shared.loggedInAccount?.account)?.isFullAccount ?? false
    }
    else {
        return (account ?? AccountsState.shared.loggedInAccount?.bgAccount)?.isFullAccount ?? false
    }
}
