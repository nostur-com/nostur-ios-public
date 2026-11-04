import Foundation
import WebKit

/// Website cookies and local storage belong to one native account. This store
/// contains website data only; no Nostur keys or database objects are exposed.
@MainActor
final class BrowserWebsiteStorage {
    static let shared = BrowserWebsiteStorage()
    private var temporaryStores: [String: WKWebsiteDataStore] = [:]

    func store(account: String, preferences: UserDefaults) -> WKWebsiteDataStore {
        guard !account.isEmpty else { return .nonPersistent() }
        let key = "browser.websiteStore.\(account)"
        let identifier: UUID
        if let saved = preferences.string(forKey: key), let uuid = UUID(uuidString: saved) {
            identifier = uuid
        } else {
            identifier = UUID()
            preferences.set(identifier.uuidString, forKey: key)
        }
        if #available(iOS 17.0, *) {
            return WKWebsiteDataStore(forIdentifier: identifier)
        }
        // Older WebKit cannot persist independent profiles, but still retains
        // logins through browser close/reopen for the lifetime of Nostur.
        if let store = temporaryStores[identifier.uuidString] { return store }
        let store = WKWebsiteDataStore.nonPersistent()
        temporaryStores[identifier.uuidString] = store
        return store
    }
}
