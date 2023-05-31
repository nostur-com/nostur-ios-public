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
        static let lastMaintenanceTimestamp = "last_maintenance_timestamp"
        
        static let isSignatureVerificationEnabled = "signature_verification_enabled"
        static let replaceNsecWithHunter2 = "replace_nsec_with_hunter2"
        
        static let defaultZapAmount = "default_zap_amount"
        static let defaultLightningWallet = "default_lightning_wallet"
        static let hideEmojisInNames = "hide_emojis_in_names"
        static let hideBadges = "hide_badges"
        static let restrictAutoDownload = "restrict_autodownload"
        static let animatedPFPenabled = "animated_pfp_enabled"
        static let rowFooterEnabled = "row_footer_enabled"
        static let autoScroll = "autoscroll"
        static let statusBubble = "statusBubble"
        static let fullWidthImages = "full_width_images"
        static let defaultMediaUploadService = "media_upload_service"
    }

//    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    public static let walletOptions = [
        LightningWallet(name: "none", scheme: "lightning:"),
        LightningWallet(name: "Zebedee", scheme: "zebedee:lightning:"), // https://documentation.zebedee.io/docs/zbd-app-uri-schemes/
        LightningWallet(name: "Wallet of Satoshi", scheme: "walletofsatoshi:lightning:"), // guessed. must check if works
        LightningWallet(name: "Muun", scheme: "muun:lightning:"), // guessed. must check if works
        LightningWallet(name: "Phoenix", scheme: "phoenix:lightning:"), // guessed. must check if works
        LightningWallet(name: "Breez", scheme: "breez:lightning:"), // https://github.com/breez/breezmobile/issues/300
        LightningWallet(name: "BlueWallet", scheme: "bluewallet:lightning:"), // https://github.com/BlueWallet/BlueWallet/wiki/Deeplinking
        LightningWallet(name: "Zeus", scheme: "zeusln:lightning:") // https://github.com/ZeusLN/zeus/blob/b0d129114390d8c6f56904e6c7a7404ca09a80f5/ios/zeus/Info.plist#LL42C5-L42C27
    ]
    
    public static let mediaUploadServiceOptions = [
        // same as imgur
        getNostrimgService(),

         // link will be just the image url but need to replace http with https
        getVoidCatService(),
        
        // needs registered Client ID
        getImgurService(),
        
        // needs registered Client ID
        getNostrCheckMeService()
    
        // no api, parse media link from response
//        getNostrBuildService(),
    ]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        defaults.register(defaults: [
            Keys.lastMaintenanceTimestamp: 0,
            Keys.replaceNsecWithHunter2: true,
            Keys.defaultZapAmount: 1000,
            Keys.hideEmojisInNames: false,
            Keys.hideBadges: false,
            Keys.restrictAutoDownload: false,
            Keys.defaultLightningWallet: SettingsStore.walletOptions.first!.id,
            Keys.animatedPFPenabled: false,
            Keys.rowFooterEnabled: true,
            Keys.autoScroll: false,
            Keys.fullWidthImages: false,
            Keys.defaultMediaUploadService: "nostrcheck.me",
            Keys.statusBubble: false
        ])

        // Don't use this anymore because re-renders too much, like when moving window on macOS
        // Manually call objectWillChange.send() now for changes that need screen updates
//        cancellable = NotificationCenter.default
//            .publisher(for: UserDefaults.didChangeNotification)
//            .print("UserDefaults.didChangeNotificatio")
//            .map { _ in () }
//            .subscribe(objectWillChange)
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
    
    var animatedPFPenabled: Bool {
        set { defaults.set(newValue, forKey: Keys.animatedPFPenabled); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.animatedPFPenabled) }
    }
    
    var rowFooterEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.rowFooterEnabled); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.rowFooterEnabled) }
    }
    
    var statusBubble: Bool {
        set { defaults.set(newValue, forKey: Keys.statusBubble); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.statusBubble) }
    }
    
    var autoScroll: Bool {
        set { defaults.set(newValue, forKey: Keys.autoScroll); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.autoScroll) }
    }
    
    var fullWidthImages: Bool {
        set { defaults.set(newValue, forKey: Keys.fullWidthImages); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.fullWidthImages) }
    }

    var hideEmojisInNames: Bool {
        set { defaults.set(newValue, forKey: Keys.hideEmojisInNames); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.hideEmojisInNames) }
    }
    
    var restrictAutoDownload: Bool {
        set { defaults.set(newValue, forKey: Keys.restrictAutoDownload); objectWillChange.send() }
        get { defaults.bool(forKey: Keys.restrictAutoDownload) }
    }
    
    var isSignatureVerificationEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.isSignatureVerificationEnabled) }
        get { defaults.bool(forKey: Keys.isSignatureVerificationEnabled) }
    }
    
    var replaceNsecWithHunter2Enabled: Bool {
        set { defaults.set(newValue, forKey: Keys.replaceNsecWithHunter2) }
        get { defaults.bool(forKey: Keys.replaceNsecWithHunter2) }
    }

    var defaultZapAmount: Double {
        set { defaults.set(newValue, forKey: Keys.defaultZapAmount) }
        get { defaults.double(forKey: Keys.defaultZapAmount) }
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
            defaults.set(newValue.id, forKey: Keys.defaultLightningWallet); objectWillChange.send()
        }
    }
}

struct LightningWallet: Identifiable, Hashable {
    var id:String { name }
    let name: String
    let scheme: String
}
