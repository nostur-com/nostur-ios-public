//
//  MediaFeedSource.swift
//  Nostur
//

import Foundation

enum MediaFeedSource: String, CaseIterable, Identifiable {
    case follows
    case webOfTrust
    case selectedRelays

    var id: String { rawValue }
}

extension Notification.Name {
    static let mediaFeedConfigurationChanged = Notification.Name("mediaFeedConfigurationChanged")
}

extension CloudFeed {
    @MainActor
    private var mediaFeedSourceKey: String {
        "mediaFeedSource_\(id?.uuidString ?? subscriptionId)"
    }

    @MainActor
    var mediaFeedSource: MediaFeedSource {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: mediaFeedSourceKey) else {
                return .follows
            }
            return MediaFeedSource(rawValue: rawValue) ?? .follows
        }
        set {
            guard newValue != mediaFeedSource else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: mediaFeedSourceKey)
            lastLocalFetchAt = nil
            sendNotification(.mediaFeedConfigurationChanged, id)
        }
    }

    @MainActor
    var mediaDiscoveryRelays: Set<RelayData> {
        let urls = relays?
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init) ?? []
        return Set(urls.map { RelayData.new(url: $0, read: true) })
    }

    @MainActor
    func mediaRelaysDidChange() {
        lastLocalFetchAt = nil
        DataProvider.shared().saveToDiskNow(.viewContext)
        sendNotification(.mediaFeedConfigurationChanged, id)
    }
}
