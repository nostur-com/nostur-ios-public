//
//  RelayConfigHealth.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2026.
//

import Foundation
import CoreData

enum RelayConfigHealth {
    /// Show the Notifications / Settings warning when receive (read) relays exceed this.
    static let maxRecommendedReadRelays = 8
    /// Target range shown in RelaysView guidance.
    static let recommendedReceiveRelayMin = 2
    static let recommendedReceiveRelayMax = 5
    static let notificationPubkey = "RELAY_CONFIG"
    static let snoozedUntilKey = "relay_config_banner_snoozed_until"
    static let snoozeMonths = 1
    
    static func looksGood(receiveCount: Int) -> Bool {
        receiveCount <= recommendedReceiveRelayMax
    }
    
    static func readRelayCount(context: NSManagedObjectContext) -> Int {
        let fr = CloudRelay.fetchRequest()
        fr.predicate = NSPredicate(format: "read == YES")
        return (try? context.count(for: fr)) ?? 0
    }
    
    static func shouldShowCompactBanner(receiveCount: Int, isSnoozed: Bool) -> Bool {
        receiveCount > maxRecommendedReadRelays && !isSnoozed
    }
    
    static func shouldShowDetailBanner(isNotOptimal: Bool, showsWhenGood: Bool) -> Bool {
        isNotOptimal || showsWhenGood
    }
    
    static func shouldCreateNotification(readCount: Int, hasExisting: Bool, isSnoozed: Bool = false) -> Bool {
        readCount > maxRecommendedReadRelays && !hasExisting && !isSnoozed
    }
    
    static func shouldRemoveNotification(readCount: Int, hasExisting: Bool) -> Bool {
        readCount <= maxRecommendedReadRelays && hasExisting
    }
    
    static func snoozeUntilDate(from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .month, value: snoozeMonths, to: now)
            ?? now.addingTimeInterval(30 * 24 * 60 * 60)
    }
    
    static func isSnoozed(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        let timestamp = defaults.double(forKey: snoozedUntilKey)
        return timestamp > now.timeIntervalSince1970
    }
    
    static func snooze(now: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(snoozeUntilDate(from: now).timeIntervalSince1970, forKey: snoozedUntilKey)
        bg().perform {
            guard let existing = PersistentNotification.fetchPersistentNotification(type: .relayConfigNotOptimal, context: bg()) else { return }
            deleteNotification(existing, context: bg())
        }
    }
    
    static func clearSnooze(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: snoozedUntilKey)
    }
    
    /// Create or remove the persistent notification based on how many relays are configured for read.
    static func check(context: NSManagedObjectContext = bg()) {
        let readCount = readRelayCount(context: context)
        let existing = PersistentNotification.fetchPersistentNotification(type: .relayConfigNotOptimal, context: context)
        let snoozed = isSnoozed()
        
        if readCount <= maxRecommendedReadRelays {
            if snoozed {
                clearSnooze()
            }
            if let existing {
                deleteNotification(existing, context: context)
            }
            return
        }
        
        if snoozed {
            if let existing {
                deleteNotification(existing, context: context)
            }
            return
        }
        
        if shouldCreateNotification(readCount: readCount, hasExisting: existing != nil, isSnoozed: snoozed) {
            let notification = PersistentNotification.createRelayConfigNotOptimal(context: context)
            DataProvider.shared().saveToDiskNow(context == bg() ? .bgContext : .viewContext)
            FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                NeedsUpdateInfo(persistentNotification: notification)
            )
        }
    }
    
    static func checkInBackground() {
        bg().perform {
            check(context: bg())
        }
    }
    
    private static func deleteNotification(_ notification: PersistentNotification, context: NSManagedObjectContext) {
        context.delete(notification)
        DataProvider.shared().saveToDiskNow(context == bg() ? .bgContext : .viewContext)
        NotificationsViewModel.shared.refreshRelayConfigUnread()
    }
}
