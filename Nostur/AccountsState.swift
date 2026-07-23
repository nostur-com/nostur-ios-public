//
//  AccountsState.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import NostrEssentials
import SwiftUI


private struct SharedShareAccount: Codable {
    let pubkey: String
    let name: String
    let pictureURL: String
    let pictureFileURL: String
    let isRemoteSigner: Bool
    let nip46Relay: String
    let remoteSignerPubkey: String
    let writeRelays: [String]
}

class AccountsState: ObservableObject {
    
    static let shared = AccountsState()
    private init() {
        self._activeAccountPublicKey = UserDefaults.standard.string(forKey: "activeAccountPublicKey") ?? ""
        Self.setSharedActiveAccountPublicKey(self._activeAccountPublicKey)
        Task { @MainActor in
            self.loadAccountsState(loadAnyAccount: true)
        }
    }
    
    @Published // Only for nil or not (onboarding), don't observe AccountsState for account switches, observe LoggedInAccount instead
    public var loggedInAccount: LoggedInAccount? = nil {
        didSet { loggedInAccount?.account.lastLoginAt = .now }
    }
    
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    
    // view context
    public var activeAccountPublicKey: String {
        get { _activeAccountPublicKey }
        set {
            self.objectWillChange.send()
            _activeAccountPublicKey = newValue
            UserDefaults.standard.setValue(newValue, forKey: "activeAccountPublicKey")
            Self.setSharedActiveAccountPublicKey(newValue)
        }
    }
    private var _activeAccountPublicKey: String
    public var accounts: [CloudAccount] = []
    
    public var fullAccounts: [CloudAccount] {
        accounts.filter { $0.isFullAccount }
    }
    
    // bgContext
    public var bgAccountPubkeys: Set<String> = []
    public var bgFullAccountPubkeys: Set<String> = []

    /// Share extension is iOS-only; do not write App Group state from Mac Catalyst.
    private static var isShareExtensionSharingEnabled: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    private static func setSharedActiveAccountPublicKey(_ pubkey: String) {
        guard isShareExtensionSharingEnabled else { return }
        let defaults = UserDefaults(suiteName: "group.com.nostur.Share")
        defaults?.setValue(pubkey, forKey: "activeAccountPublicKey")
        defaults?.synchronize()
    }

    private static func setSharedWriteRelayList(_ relayUrls: [String]) {
        guard isShareExtensionSharingEnabled else { return }
        let defaults = UserDefaults(suiteName: "group.com.nostur.Share")
        defaults?.set(relayUrls, forKey: "write_relay_list")
        defaults?.synchronize()
    }

    private static func setSharedAccountState(account: CloudAccount?) {
        guard isShareExtensionSharingEnabled else { return }
        let defaults = UserDefaults(suiteName: "group.com.nostur.Share")
        let accountPicture = (account?.pictureUrl?.absoluteString ?? account?.picture ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contactPicture = account
            .flatMap { Contact.fetchByPubkey($0.publicKey, context: context())?.picture }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        let pictureURLString = accountPicture.isEmpty ? contactPicture : accountPicture

        defaults?.set(account?.anyName ?? "", forKey: "activeAccountName")
        defaults?.set(pictureURLString, forKey: "activeAccountPictureURL")
        defaults?.set(sharedCachedProfileImageURL(for: pictureURLString, pubkey: account?.publicKey ?? "active")?.absoluteString ?? "", forKey: "activeAccountPictureFileURL")
        defaults?.set(account?.isNC == true, forKey: "activeAccountIsRemoteSigner")
        defaults?.set(account?.ncRelay ?? "", forKey: "activeAccountNip46Relay")
        defaults?.set(account?.ncRemoteSignerPubkey ?? "", forKey: "activeAccountRemoteSignerPubkey")
        defaults?.synchronize()
    }

    private static func sharedCachedProfileImageURL(for pictureURLString: String, pubkey: String) -> URL? {
        guard isShareExtensionSharingEnabled else { return nil }
        let fileName = "account-pfp-\(pubkey).png"
        guard let pictureURL = URL(string: pictureURLString),
              hasFPFcacheFor(pfpImageRequestFor(pictureURL)),
              let image = ImageProcessing.shared.pfp.cache.cachedImage(for: pfpImageRequestFor(pictureURL))?.image,
              let imageData = image.pngData(),
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nostur.Share") else {
            removeSharedCachedProfileImage(fileName: fileName)
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(fileName)
        do {
            try imageData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            removeSharedCachedProfileImage(fileName: fileName)
            return nil
        }
    }

    private static func removeSharedCachedProfileImage(fileName: String) {
        guard isShareExtensionSharingEnabled else { return }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nostur.Share") else { return }
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(fileName))
    }

    /// Write relays the share extension should use for `account`.
    /// Always app-level `CloudRelay` write flags (Relays UI / ConnectionPool) — never kind:10002 `accountRelays`.
    @MainActor private static func effectiveWriteRelayUrls(for account: CloudAccount?) -> [String] {
        let activePubkey = account?.publicKey ?? ""
        let cloudWriteRelays = CloudRelay.fetchAll(context: context())
            .filter { $0.write }
            .filter { activePubkey.isEmpty || !$0.excludedPubkeys.contains(activePubkey) }
            .map { normalizeRelayUrl($0.url_ ?? "") }
            .filter { Self.isShareExtensionRelayUrl($0) }

        return Array(Set(cloudWriteRelays)).sorted()
    }

    private static func isShareExtensionRelayUrl(_ relayUrl: String) -> Bool {
        guard relayUrl.hasPrefix("wss://") else { return false }
        return !relayUrl.contains("/localhost")
            && !relayUrl.contains("s://127.0")
            && relayUrl != "local"
            && relayUrl != "iCloud"
    }

    @MainActor private func mirrorShareExtensionAccountState(account: CloudAccount?) {
        guard Self.isShareExtensionSharingEnabled else { return }
        Self.setSharedWriteRelayList(Self.effectiveWriteRelayUrls(for: account))
        Self.setSharedAccountState(account: account)
        Self.setSharedAccounts(accounts.filter { $0.isFullAccount })
    }

    /// Call after relay list / write flags change so the share extension does not keep a stale list.
    /// No-op on Mac Catalyst (share extension is iOS-only).
    @MainActor public func refreshShareExtensionAccountState() {
        guard Self.isShareExtensionSharingEnabled else { return }
        let activeAccount = accounts.first(where: { $0.publicKey == activeAccountPublicKey })
            ?? loggedInAccount?.account
        mirrorShareExtensionAccountState(account: activeAccount)
    }

    @MainActor private static func setSharedAccounts(_ accounts: [CloudAccount]) {
        guard isShareExtensionSharingEnabled else { return }
        let sharedAccounts = accounts.map { account in
            let accountPicture = (account.pictureUrl?.absoluteString ?? account.picture)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let contactPicture = (Contact.fetchByPubkey(account.publicKey, context: context())?.picture ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pictureURLString = accountPicture.isEmpty ? contactPicture : accountPicture

            return SharedShareAccount(
                pubkey: account.publicKey,
                name: account.anyName,
                pictureURL: pictureURLString,
                pictureFileURL: sharedCachedProfileImageURL(for: pictureURLString, pubkey: account.publicKey)?.absoluteString ?? "",
                isRemoteSigner: account.isNC,
                nip46Relay: account.ncRelay,
                remoteSignerPubkey: account.ncRemoteSignerPubkey,
                writeRelays: effectiveWriteRelayUrls(for: account)
            )
        }

        let defaults = UserDefaults(suiteName: "group.com.nostur.Share")
        if let data = try? JSONEncoder().encode(sharedAccounts) {
            defaults?.set(data, forKey: "share_accounts")
        }
        defaults?.synchronize()
    }

    @MainActor public func loadAccountsState(loadAnyAccount: Bool = false) {
        self.accounts = CloudAccount.fetchAccounts(context: context())
        let accountPubkeys = Set(accounts.map { $0.publicKey })
        let fullAccountPubkeys = Set(accounts.filter { $0.isFullAccount }.map { $0.publicKey })
        bg().perform {
            self.bgAccountPubkeys = accountPubkeys
            self.bgFullAccountPubkeys = fullAccountPubkeys
        }
        
        let activeAccount = accounts.first(where: { $0.publicKey == activeAccountPublicKey })
        mirrorShareExtensionAccountState(account: activeAccount)

        // No account selected
        if activeAccountPublicKey.isEmpty && !loadAnyAccount {
            self.loggedInAccount = nil
            sendNotification(.clearNavigation)
            return
        }
        else if !activeAccountPublicKey.isEmpty, let account = activeAccount {
            if loggedInAccount?.account != account {
                Task { @MainActor in
                    changeAccount(account)
                }
            }
        }
        // can't find account, change to last active account. Never auto-activate the guest account
        // here: it is pre-created as a prefetch on first launch (initializeGuestAccount) and should
        // only become active by explicit user action (same exclusion as Onboarding.onAppear).
        else if let nextAccount = accounts.sorted(by: { $0.lastLoginAt > $1.lastLoginAt }).first(where: { $0.publicKey != GUEST_ACCOUNT_PUBKEY }), loadAnyAccount {
            Task { @MainActor in
                changeAccount(nextAccount)
            }
        }
        else { // we don't have any accounts
            self.loggedInAccount = nil
            sendNotification(.clearNavigation)
        }
    }
    
    @MainActor public func logout(_ account: CloudAccount) {
        let logoutAccountPubkey = account.publicKey

        // Remote-signer (NIP-46) account: tell the signer (e.g. Clave/Spectr) to tear down this
        // pairing, then delete our session keypair. Must happen before deleting the account, since
        // sending the logout needs the session key. The signer auto-allows logout and no-ops if
        // there is no live session, so this is safe even if the pairing was never fully established.
        if account.isNC {
            RemoteSignerManager.shared.logout(usingAccount: account)
            NIP46SecretManager.shared.deleteSecret(account: account)
        }

        DataProvider.shared().viewContext.delete(account)
        DataProvider.shared().saveToDiskNow(.viewContext)
        
        guard logoutAccountPubkey == self.activeAccountPublicKey else { return }
        
        self.activeAccountPublicKey = ""
        mirrorShareExtensionAccountState(account: nil)
        self.loadAccountsState(loadAnyAccount: true)
        AccountManager.shared.cleanUp(for: logoutAccountPubkey)
    }

    @MainActor // changeAccount changes th .account in LoggedInAccount, so cannot be nil. For nil, set loggedInAccount to nil instead
    public func changeAccount(_ account: CloudAccount) {
        self.activeAccountPublicKey = account.publicKey
        if account.isNC {
            RemoteSignerManager.shared.setAccount(account)
        }
        let pubkey = account.publicKey
        
        if self.loggedInAccount == nil {
            self.loggedInAccount = LoggedInAccount(account)
        }
        else {
            self.loggedInAccount?.account = account
        }
        mirrorShareExtensionAccountState(account: account)
        
        self.loadAccountsState()
        sendNotification(.activeAccountChanged, account)
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

func account(by accountPubkey: String? = nil) -> CloudAccount? {
    if let accountPubkey {
        if Thread.isMainThread {
            return AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) ?? (try? CloudAccount.fetchAccount(publicKey: accountPubkey, context: context()))
        }
        else {
            return try? CloudAccount.fetchAccount(publicKey: accountPubkey, context: context())
        }
    }
    
    
    if Thread.isMainThread {
        return AccountsState.shared.loggedInAccount?.account ?? (try? CloudAccount.fetchAccount(publicKey: AccountsState.shared.activeAccountPublicKey, context: context()))
    }
    else {
        return AccountsState.shared.loggedInAccount?.bgAccount ?? (try? CloudAccount.fetchAccount(publicKey: AccountsState.shared.activeAccountPublicKey, context: context()))
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
