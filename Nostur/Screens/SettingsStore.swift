//
//  SettingsStore.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/02/2023.
//

import Foundation
import SwiftUI
import Combine

final class SettingsStore: ObservableObject {
    
    public static let shared = SettingsStore()
    
    public enum Keys {
        static let lastMaintenanceTimestamp:String = "last_maintenance_timestamp"
        
        static let isSignatureVerificationEnabled:String = "signature_verification_enabled"
        static let replaceNsecWithHunter2:String = "replace_nsec_with_hunter2"
        
        static let defaultZapAmount:String = "default_zap_amount"
        static let defaultLightningWallet:String = "default_lightning_wallet"
//        static let hideEmojisInNames:String = "hide_emojis_in_names"
        static let hideBadges:String = "hide_badges"
        static let autoDownloadFrom:String = "autodownload_from"
        static let thunderzapLevel:String = "thunderzal_level"
        static let restrictAutoDownload:String = "restrict_autodownload"
        static let animatedPFPenabled:String = "animated_pfp_enabled"
        static let rowFooterEnabled:String = "row_footer_enabled"
        static let autoScroll:String = "autoscroll"
        static let statusBubble:String = "statusBubble"
        static let fullWidthImages:String = "full_width_images"
        static let defaultMediaUploadService:String = "media_upload_service"
        static let activeNWCconnectionId:String = "active_nwc_connection_id"
        static let fetchCounts:String = "fetch_counts"
        static let includeSharedFrom:String = "include_shared_from"
        
        static let webOfTrustLevel:String = "web_of_trust_level"
        static let autoHideBars:String = "auto_hide_bars"
        static let lowDataMode:String = "low_data_mode"
        static let footerButtons:String = "footer_buttons"
        
        static let nwcShowBalance:String = "nwc_show_balance"
        static let appWideSeenTracker:String = "app_wide_seen_tracker"
        static let mainWoTaccountPubkey:String = "main_wot_account_pubkey"
        
        static let postUserAgentEnabled:String = "post_user_agent_enabled"
        static let displayUserAgentEnabled:String = "display_user_agent_enabled"
        static let excludedUserAgentPubkeys:String = "excluded_user_agent_pubkeys"
        
        static let receiveLocalNotifications:String = "receive_local_notifications"
        static let receiveLocalNotificationsLimitToFollows:String = "receive_local_notifications_limit_to_follows"
        
        static let proMode:String = "nostur_pro_mode"
    }

//    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()
    
    enum WebOfTrustLevel:String, CaseIterable, Localizable, Identifiable {
        case off = "WOT_OFF"
        case normal = "WOT_NORMAL"
        case strict = "WOT_STRICT"
        
        var id:String {
            String(self.rawValue)
        }
    }
    
    public static let walletOptions:[LightningWallet] = [
        LightningWallet(name: "none", scheme: "lightning:"),
        LightningWallet(name: "Zebedee", scheme: "zebedee:lightning:"), // https://documentation.zebedee.io/docs/zbd-app-uri-schemes/
        LightningWallet(name: "Wallet of Satoshi", scheme: "walletofsatoshi:lightning:"), // guessed. must check if works
        LightningWallet(name: "Muun", scheme: "muun:lightning:"), // guessed. must check if works
        LightningWallet(name: "Phoenix", scheme: "phoenix:lightning:"), // guessed. must check if works
        LightningWallet(name: "Breez", scheme: "breez:lightning:"), // https://github.com/breez/breezmobile/issues/300
        LightningWallet(name: "BlueWallet", scheme: "bluewallet:lightning:"), // https://github.com/BlueWallet/BlueWallet/wiki/Deeplinking
        LightningWallet(name: "Zeus", scheme: "zeusln:lightning:"), // https://github.com/ZeusLN/zeus/blob/b0d129114390d8c6f56904e6c7a7404ca09a80f5/ios/zeus/Info.plist#LL42C5-L42C27
        LightningWallet(name: "Alby (Nostr Wallet Connect)", scheme: "nostur:nwc:alby:"), // NWC
        LightningWallet(name: "Custom Nostr Wallet Connect...", scheme: "nostur:nwc:custom:") // CUSTOM NWC
    ]
    
    public static let mediaUploadServiceOptions:[MediaUploadService] = [
        // same as imgur
        getNostrimgService(),

         // link will be just the image url but need to replace http with https
        getVoidCatService(),
        
        // needs registered Client ID
        getImgurService(),
        
        // needs registered Client ID
        getNostrCheckMeService(),
        
        // url in json response but need to replace http with https
        getNostrFilesDevService(),
    
        // no api, parse media link from response
//        getNostrBuildService(),
        
        MediaUploadService(name: "nostr.build", request: { imageData, usePNG in
            // Dummy function body just to be compatible with MediaUploadService
            // We only need .name for the Picker in Settings, handle actual implementation with NostrEssentials Nip96Uploader
            let url = URL(string: "https://localhost")!
            var request = URLRequest(url: url)
            return request
        }, urlFromResponse: { (data, response, _) in
            // Dummy function body just to be compatible with MediaUploadService
            // We only need .name for the Picker in Settings, handle actual implementation with NostrEssentials Nip96Uploader
            return "https://localhost"
        }),
        
        MediaUploadService(name: "Custom File Storage (NIP-96)", request: { imageData, usePNG in
            // Dummy function body just to be compatible with MediaUploadService
            // We only need .name for the Picker in Settings, handle actual implementation with NostrEssentials Nip96Uploader
            let url = URL(string: "https://localhost")!
            var request = URLRequest(url: url)
            return request
        }, urlFromResponse: { (data, response, _) in
            // Dummy function body just to be compatible with MediaUploadService
            // We only need .name for the Picker in Settings, handle actual implementation with NostrEssentials Nip96Uploader
            return "https://localhost"
        })
    ]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        defaults.register(defaults: [
            Keys.lastMaintenanceTimestamp: 0,
            Keys.replaceNsecWithHunter2: true,
            Keys.defaultZapAmount: 21,
//            Keys.hideEmojisInNames: false,
            Keys.hideBadges: false,
            Keys.autoDownloadFrom: AutodownloadLevel.onlyWoT.rawValue,
            Keys.thunderzapLevel: ThunderzapLevel.normal.rawValue,
            Keys.restrictAutoDownload: false,
            Keys.defaultLightningWallet: SettingsStore.walletOptions.first!.id,
            Keys.animatedPFPenabled: false,
            Keys.rowFooterEnabled: true,
            Keys.autoScroll: false,
            Keys.fullWidthImages: false,
            Keys.defaultMediaUploadService: "nostrcheck.me",
            Keys.statusBubble: false,
            Keys.activeNWCconnectionId: "",
            Keys.fetchCounts: false,
            Keys.webOfTrustLevel: WebOfTrustLevel.normal.rawValue,
            Keys.includeSharedFrom: true,
            Keys.autoHideBars: false,
            Keys.isSignatureVerificationEnabled: true,
            Keys.lowDataMode: false,
            Keys.nwcShowBalance: false,
            Keys.footerButtons: IS_APPLE_TYRANNY ? "💬🔄+🔖" : "💬🔄+⚡️🔖",
            Keys.appWideSeenTracker: true,
            Keys.mainWoTaccountPubkey: "",
            Keys.postUserAgentEnabled: true,
            Keys.displayUserAgentEnabled: true,
            Keys.excludedUserAgentPubkeys: "",
            Keys.receiveLocalNotifications: true,
            Keys.receiveLocalNotificationsLimitToFollows: false,
            Keys.proMode: false
        ])

        // Don't use this anymore because re-renders too much, like when moving window on macOS
        // Manually call objectWillChange.send() now for changes that need screen updates
//        cancellable = NotificationCenter.default
//            .publisher(for: UserDefaults.didChangeNotification)
//            .print("UserDefaults.didChangeNotificatio")
//            .map { _ in () }
//            .subscribe(objectWillChange)
        
        // TODO: Refactor settings, better use all properties on SettingsStore directly instead of (slower) defaults.bool()
        // for now only a few that we need right now:
        _animatedPFPenabledCache = defaults.bool(forKey: Keys.animatedPFPenabled)
        _lowDataModeCache = defaults.bool(forKey: Keys.lowDataMode)
        _rowFooterEnabled = defaults.bool(forKey: Keys.rowFooterEnabled)
        _displayUserAgentEnabled = defaults.bool(forKey: Keys.displayUserAgentEnabled)
        _restrictAutoDownload = defaults.bool(forKey: Keys.restrictAutoDownload)
        _autoDownloadFrom = defaults.string(forKey: Keys.autoDownloadFrom) ?? AutodownloadLevel.onlyWoT.rawValue
        _fullWidthImages = defaults.bool(forKey: Keys.fullWidthImages)
        _footerButtons = defaults.string(forKey: Keys.footerButtons) ?? "💬🔄+🔖"
        DispatchQueue.main.async {
            ViewModelCache.shared.footerButtons = self._footerButtons
        }
        _fetchCounts = defaults.bool(forKey: Keys.fetchCounts)
        _appWideSeenTracker = defaults.bool(forKey: Keys.appWideSeenTracker)
        _mainWoTaccountPubkey = defaults.string(forKey: Keys.mainWoTaccountPubkey) ?? ""
        
        // optimize
        self.updateNWCreadyCache()
    }
    
    var defaultMediaUploadService: MediaUploadService {
        get {
            return defaults.string(forKey: Keys.defaultMediaUploadService)
                .flatMap { id in
                    SettingsStore.mediaUploadServiceOptions.first(where: { service in
                        return service.id == id
                    })
                } ?? SettingsStore.mediaUploadServiceOptions.first!
        }

        set {
            defaults.set(newValue.id, forKey: Keys.defaultMediaUploadService); objectWillChange.send()
        }
    }
    
    var lastMaintenanceTimestamp: Int {
        set { defaults.set(newValue, forKey: Keys.lastMaintenanceTimestamp) }
        get { defaults.integer(forKey: Keys.lastMaintenanceTimestamp) }
    }
    
    var hideBadges: Bool {
        set { defaults.set(newValue, forKey: Keys.hideBadges); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.hideBadges) }
    }
    
    var includeSharedFrom: Bool {
        set { defaults.set(newValue, forKey: Keys.includeSharedFrom); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.includeSharedFrom) }
    }
    
    var postUserAgentEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.postUserAgentEnabled); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.postUserAgentEnabled) }
    }

    var statusBubble: Bool {
        set { defaults.set(newValue, forKey: Keys.statusBubble); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.statusBubble) }
    }
    
    var autoScroll: Bool {
        set { defaults.set(newValue, forKey: Keys.autoScroll); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.autoScroll) }
    }
    
    
    var nwcShowBalance: Bool {
        set { defaults.set(newValue, forKey: Keys.nwcShowBalance); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.nwcShowBalance) }
    }

//    var hideEmojisInNames: Bool {
//        set { defaults.set(newValue, forKey: Keys.hideEmojisInNames); objectWillChange.send() }
//        get { defaults.bool(forKey: Keys.hideEmojisInNames) }
//    }
    
    var isSignatureVerificationEnabled: Bool {
        set { 
            defaults.set(newValue, forKey: Keys.isSignatureVerificationEnabled)
            bg().perform {
                MessageParser.shared.isSignatureVerificationEnabled = newValue
            }
        }
        get { defaults.bool(forKey: Keys.isSignatureVerificationEnabled) }
    }
    
    var replaceNsecWithHunter2Enabled: Bool {
        set { defaults.set(newValue, forKey: Keys.replaceNsecWithHunter2) }
        get { defaults.bool(forKey: Keys.replaceNsecWithHunter2) }
    }
    
    var proMode: Bool {
        set { objectWillChange.send(); defaults.set(newValue, forKey: Keys.proMode) }
        get { defaults.bool(forKey: Keys.proMode) }
    }

    var defaultZapAmount: Double {
        set { objectWillChange.send(); defaults.set(newValue, forKey: Keys.defaultZapAmount) }
        get { defaults.double(forKey: Keys.defaultZapAmount) }
    }
    
    var activeNWCconnectionId: String {
        set {
            objectWillChange.send();
            defaults.set(newValue, forKey: Keys.activeNWCconnectionId)
            updateNWCreadyCache()
        }
        get { defaults.string(forKey: Keys.activeNWCconnectionId) ?? "" }
    }
    
    var excludedUserAgentPubkeys: Set<String> {
        set {
            objectWillChange.send();
            defaults.set(newValue.joined(separator: " "), forKey: Keys.excludedUserAgentPubkeys)
        }
        get {
            guard let pubkeys = defaults.string(forKey: Keys.excludedUserAgentPubkeys) else { return [] }
            return Set(pubkeys.components(separatedBy: " "))
        }
    }

    var autoHideBars: Bool {
        set { defaults.set(newValue, forKey: Keys.autoHideBars); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.autoHideBars) }
    }

    var defaultLightningWallet: LightningWallet {
        get {
            return defaults.string(forKey: Keys.defaultLightningWallet)
                .flatMap { id in
                    SettingsStore.walletOptions.first(where: { wallet in
                        return wallet.id == id
                    })
                } ?? SettingsStore.walletOptions.first!
        }

        set {
            objectWillChange.send()
            defaults.set(newValue.id, forKey: Keys.defaultLightningWallet);
            updateNWCreadyCache()
        }
    }
    
    var receiveLocalNotifications: Bool {
        set { defaults.set(newValue, forKey: Keys.receiveLocalNotifications); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.receiveLocalNotifications) }
    }    
    
    var receiveLocalNotificationsLimitToFollows: Bool {
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.receiveLocalNotificationsLimitToFollows);
        }
        get { defaults.bool(forKey: Keys.receiveLocalNotificationsLimitToFollows) }
    }
    
    var thunderzapLevel: String {
        set {
            objectWillChange.send();
            defaults.set(newValue, forKey: Keys.thunderzapLevel)
        }
        get { defaults.string(forKey: Keys.thunderzapLevel) ?? ThunderzapLevel.normal.rawValue }
    }
    
    // MARK: -- SPECIAL HANDLING FOR PERFORMANCE ON EVERYTHING BELOW:
    
    var webOfTrustLevel: String {
        set {
            objectWillChange.send(); defaults.set(newValue, forKey: Keys.webOfTrustLevel)
            WebOfTrust.shared.webOfTrustLevel = newValue
        }
        get { defaults.string(forKey: Keys.webOfTrustLevel) ?? WebOfTrustLevel.normal.rawValue }
    }
    
    // Instruments:
    // 10.00 ms    0.0%    0 s           SettingsStore.animatedPFPenabled.getter
    public var animatedPFPenabled: Bool {
        set {
            objectWillChange.send()
            _animatedPFPenabledCache = newValue
            defaults.set(newValue, forKey: Keys.animatedPFPenabled);
        }
        get { _animatedPFPenabledCache }
    }
    
    private var _animatedPFPenabledCache:Bool = false
    
    public var lowDataMode: Bool {
        set {
            objectWillChange.send()
            _lowDataModeCache = newValue
            defaults.set(newValue, forKey: Keys.lowDataMode);
        }
        get { _lowDataModeCache }
    }
    
    private var _lowDataModeCache:Bool = false
    
    var rowFooterEnabled: Bool {
        set {
            objectWillChange.send()
            _rowFooterEnabled = newValue
            defaults.set(newValue, forKey: Keys.rowFooterEnabled);
            if !newValue {
                defaults.set(false, forKey: Keys.fetchCounts);
            }
        }
        get { _rowFooterEnabled }
    }
    
    private var _rowFooterEnabled:Bool = true
    
    var displayUserAgentEnabled: Bool {
        set {
            objectWillChange.send()
            _displayUserAgentEnabled = newValue
            defaults.set(newValue, forKey: Keys.displayUserAgentEnabled);
        }
        get { _displayUserAgentEnabled }
    }
    
    private var _displayUserAgentEnabled:Bool = true
    
    public var restrictAutoDownload: Bool {
        set {
            objectWillChange.send()
            _restrictAutoDownload = newValue
            defaults.set(newValue, forKey: Keys.restrictAutoDownload);
        }
        get { _restrictAutoDownload }
    }
    
    private var _restrictAutoDownload:Bool = false
    
    public var autoDownloadFrom: String {
        set {
            objectWillChange.send(); defaults.set(newValue, forKey: Keys.autoDownloadFrom)
            _autoDownloadFrom = newValue
        }
        get { defaults.string(forKey: Keys.autoDownloadFrom) ?? AutodownloadLevel.onlyWoT.rawValue }
    }
    
    private var _autoDownloadFrom:String = AutodownloadLevel.onlyWoT.rawValue
    
    public var fullWidthImages: Bool {
        set {
            objectWillChange.send()
            _fullWidthImages = newValue
            defaults.set(newValue, forKey: Keys.fullWidthImages);
        }
        get { _fullWidthImages }
    }
    
    private var _fullWidthImages:Bool = false
    
    public var footerButtons: String {
        set {
            objectWillChange.send()
            _footerButtons = newValue
            defaults.set(newValue, forKey: Keys.footerButtons);
            ViewModelCache.shared.footerButtons = newValue
        }
        get { _footerButtons }
    }
    
    private var _footerButtons:String = IS_APPLE_TYRANNY ? "💬🔄+🔖" : "💬🔄+⚡️🔖"
    
    public var fetchCounts: Bool {
        set {
            objectWillChange.send()
            _fetchCounts = newValue
            defaults.set(newValue, forKey: Keys.fetchCounts);
        }
        get { _fetchCounts }
    }
    
    private var _fetchCounts:Bool = false
    
    public var appWideSeenTracker: Bool {
        set {
            objectWillChange.send()
            _appWideSeenTracker = newValue
            defaults.set(newValue, forKey: Keys.appWideSeenTracker);
        }
        get { _appWideSeenTracker }
    }
    
    private var _appWideSeenTracker:Bool = false
    
    
    // optimize
    
    public var nwcReady:Bool = false
    
    private func isNWCready() -> Bool {
        defaultLightningWallet.scheme.contains(":nwc:") && !activeNWCconnectionId.isEmpty
    }
    private func updateNWCreadyCache() {
        DispatchQueue.main.async {
            self.objectWillChange.send();
            self.nwcReady = self.isNWCready()
        }
    }
    
    public var mainWoTaccountPubkey: String {
        set {
            objectWillChange.send()
            _mainWoTaccountPubkey = newValue
            defaults.set(newValue, forKey: Keys.mainWoTaccountPubkey);
        }
        get { _mainWoTaccountPubkey }
    }
    
    private var _mainWoTaccountPubkey:String = ""
    
    static func shouldAutodownload(_ nrPost:NRPost) -> Bool {
        if nrPost.following { return true }
        switch SettingsStore.shared.autoDownloadFrom {
        case AutodownloadLevel.all.rawValue:
            return true
        case AutodownloadLevel.onlyWoT.rawValue:
            guard WebOfTrust.shared.tresholdReached else { return true }
            return WebOfTrust.shared.isAllowed(nrPost.pubkey)
        case AutodownloadLevel.onlyWoTstrict.rawValue:
            return isFollowing(nrPost.pubkey)
        default:
            return true
        }
    }
}

struct LightningWallet: Identifiable, Hashable {
    var id:String { name }
    let name: String
    let scheme: String
}



enum AutodownloadLevel:String, CaseIterable, Localizable, Identifiable {
    case all = "AUTODOWNLOAD_ALL"
    case onlyWoT = "AUTODOWNLOAD_WOT_NORMAL"
    case onlyWoTstrict = "AUTODOWNLOAD_WOT_STRICT"
    
    var id:String {
        String(self.rawValue)
    }
}

enum ThunderzapLevel:String, CaseIterable, Localizable, Identifiable {
    case normal = "THUNDERZAP_NORMAL"
    case low = "THUNDERZAP_LOW"
    case off = "THUNDERZAP_OFF"
    
    var id:String {
        String(self.rawValue)
    }
}
