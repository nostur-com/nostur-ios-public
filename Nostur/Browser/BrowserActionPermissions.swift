import Foundation

struct BrowserActionGrant: Identifiable {
    let kind: Int
    let expiresAt: Date
    var destination: String? = nil
    var id: String { destination ?? String(kind) }
    var isPermanent: Bool { expiresAt == .distantFuture }
}

enum BrowserGrantDuration { case once, today, always }

/// Native-only grants. A web page never supplies the account, origin or expiry.
struct BrowserActionPermissions {
    let preferences: UserDefaults

    private func key(account: String, origin: String) -> String {
        "browser.actionGrants.\(account).\(origin)"
    }
    func grants(account: String, origin: String, now: Date = Date()) -> [BrowserActionGrant] {
        let values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        return values.compactMap { key, value in
            guard let expiry = value as? Double, expiry.isFinite,
                  expiry > now.timeIntervalSince1970 else { return nil }
            let expiresAt = Date(timeIntervalSince1970: expiry)
            if let kind = Int(key), BrowserSigningPolicy.canGrant(kind) {
                return BrowserActionGrant(kind: kind, expiresAt: expiresAt)
            }
            guard key != origin, BrowserSigningPolicy.origin(URL(string: key)) == key else { return nil }
            return BrowserActionGrant(kind: 27235, expiresAt: expiresAt, destination: key)
        }.sorted { $0.id < $1.id }
    }
    func allow(kind: Int, account: String, origin: String, duration: BrowserGrantDuration, destination: String? = nil,
               now: Date = Date(), calendar: Calendar = .current) {
        guard duration != .once, BrowserSigningPolicy.canGrant(kind), !account.isEmpty,
              BrowserSigningPolicy.origin(URL(string: origin)) == origin else { return }
        if let destination {
            guard kind == 27235, destination != origin,
                  BrowserSigningPolicy.origin(URL(string: destination)) == destination else { return }
        }
        let expiry = duration == .always ? Date.distantFuture : calendar.dateInterval(of: .day, for: now)?.end
        guard let expiry else { return }
        var values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        values[destination ?? String(kind)] = expiry.timeIntervalSince1970
        preferences.set(values, forKey: key(account: account, origin: origin))
    }
    func revoke(kind: Int, account: String, origin: String, destination: String? = nil) {
        var values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        values.removeValue(forKey: destination ?? String(kind))
        preferences.set(values, forKey: key(account: account, origin: origin))
    }
}

struct BrowserBlockedRequest: Identifiable {
    let id: UUID
    let scope: BrowserRequestScope
    let kind: Int
    let reason: String
    let canAllow: Bool
    var waiting: Bool
    var destination: String? = nil
    var event: BrowserUnsignedEvent? = nil
    var actionName: String {
        if let event { return BrowserEventDescription.name(for: event) }
        return kind < 0 ? String(localized: "Account connection") : BrowserEventDescription.name(for: kind)
    }
}
