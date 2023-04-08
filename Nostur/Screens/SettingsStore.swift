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
        static let pro = "pro"
        static let sleepGoal = "sleep_goal"
        
        static let isSignatureVerificationEnabled = "signature_verification_enabled"
        static let replaceNsecWithHunter2 = "replace_nsec_with_hunter2"
        static let sleepTrackingEnabled = "sleep_tracking_enabled"
        static let sleepTrackingMode = "sleep_tracking_mode"
        
        static let defaultZapAmount = "default_zap_amount"
        static let defaultLightningWallet = "default_lightning_wallet"
        static let hideEmojisInNames = "hide_emojis_in_names"
        static let hideBadges = "hide_badges"
        static let restrictAutoDownload = "restrict_autodownload"
        static let animatedPFPenabled = "animated_pfp_enabled"
    }

    private let cancellable: Cancellable
    private let defaults: UserDefaults

    let objectWillChange = PassthroughSubject<Void, Never>()

    public static let walletOptions = [
        LightningWallet(name: "none", scheme: "lightning:"),
        LightningWallet(name: "Zebedee", scheme: "zebedee:lightning:"), // https://documentation.zebedee.io/docs/zbd-app-uri-schemes/
        LightningWallet(name: "Wallet of Satoshi", scheme: "walletofsatoshi:lightning:"), // guessed. must check if works
        LightningWallet(name: "Muun", scheme: "muun:lightning:"), // guessed. must check if works
        LightningWallet(name: "Phoenix", scheme: "phoenix:lightning:"), // guessed. must check if works
        LightningWallet(name: "Breez", scheme: "breez:lightning:"), // https://github.com/breez/breezmobile/issues/300
        LightningWallet(name: "BlueWallet", scheme: "bluewallet:lightning:") // https://github.com/BlueWallet/BlueWallet/wiki/Deeplinking
    ]
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        defaults.register(defaults: [
            Keys.replaceNsecWithHunter2: true,
            Keys.sleepGoal: 8,
            Keys.defaultZapAmount: 1000,
            Keys.sleepTrackingEnabled: true,
            Keys.hideEmojisInNames: false,
            Keys.hideBadges: false,
            Keys.restrictAutoDownload: true,
            Keys.defaultLightningWallet: SettingsStore.walletOptions.first!.id,
            Keys.animatedPFPenabled: true,
            ])

        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .map { _ in () }
            .subscribe(objectWillChange)
    }
    
    var hideBadges: Bool {
        set { defaults.set(newValue, forKey: Keys.hideBadges) }
        get { defaults.bool(forKey: Keys.hideBadges) }
    }
    
    var animatedPFPenabled: Bool {
        set { defaults.set(newValue, forKey: Keys.animatedPFPenabled) }
        get { defaults.bool(forKey: Keys.animatedPFPenabled) }
    }
    

    var hideEmojisInNames: Bool {
        set { defaults.set(newValue, forKey: Keys.hideEmojisInNames) }
        get { defaults.bool(forKey: Keys.hideEmojisInNames) }
    }
    
    var restrictAutoDownload: Bool {
        set { defaults.set(newValue, forKey: Keys.restrictAutoDownload) }
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

    var isPro: Bool {
        set { defaults.set(newValue, forKey: Keys.pro) }
        get { defaults.bool(forKey: Keys.pro) }
    }

    var isSleepTrackingEnabled: Bool {
        set { defaults.set(newValue, forKey: Keys.sleepTrackingEnabled) }
        get { defaults.bool(forKey: Keys.sleepTrackingEnabled) }
    }

    var sleepGoal: Int {
        set { defaults.set(newValue, forKey: Keys.sleepGoal) }
        get { defaults.integer(forKey: Keys.sleepGoal) }
    }
    
    var defaultZapAmount: Double {
        set { defaults.set(newValue, forKey: Keys.defaultZapAmount) }
        get { defaults.double(forKey: Keys.defaultZapAmount) }
    }

    enum SleepTrackingMode: String, CaseIterable {
        case low
        case moderate
        case aggressive
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
            defaults.set(newValue.id, forKey: Keys.defaultLightningWallet)
        }
    }
}

extension SettingsStore {
    func unlockPro() {
        // You can do your in-app transactions here
        isPro = true
    }

    func restorePurchase() {
        // You can do you in-app purchase restore here
        isPro = true
    }
}


struct LightningWallet: Identifiable, Hashable {
    var id:String { name }
    let name: String
    let scheme: String
}
