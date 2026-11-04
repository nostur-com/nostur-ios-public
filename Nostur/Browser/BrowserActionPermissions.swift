import Foundation

struct BrowserActionGrant: Identifiable {
    let kind: Int
    let expiresAt: Date
    var id: Int { kind }
    var isPermanent: Bool { expiresAt == .distantFuture }
}

enum BrowserGrantDuration { case today, always }

/// Native-only grants. A web page never supplies the account, origin or expiry.
struct BrowserActionPermissions {
    let preferences: UserDefaults

    private func key(account: String, origin: String) -> String {
        "browser.actionGrants.\(account).\(origin)"
    }
    func grants(account: String, origin: String, now: Date = Date()) -> [BrowserActionGrant] {
        let values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        return values.compactMap { kind, value in
            guard let kind = Int(kind), BrowserSigningPolicy.canGrant(kind),
                  let expiry = value as? Double, expiry.isFinite, expiry > now.timeIntervalSince1970 else { return nil }
            return BrowserActionGrant(kind: kind, expiresAt: Date(timeIntervalSince1970: expiry))
        }.sorted { $0.kind < $1.kind }
    }
    func allow(kind: Int, account: String, origin: String, duration: BrowserGrantDuration,
               now: Date = Date(), calendar: Calendar = .current) {
        guard BrowserSigningPolicy.canGrant(kind), !account.isEmpty,
              BrowserSigningPolicy.origin(URL(string: origin)) == origin else { return }
        let expiry = duration == .always ? Date.distantFuture : calendar.dateInterval(of: .day, for: now)?.end
        guard let expiry else { return }
        var values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        values[String(kind)] = expiry.timeIntervalSince1970
        preferences.set(values, forKey: key(account: account, origin: origin))
    }
    func revoke(kind: Int, account: String, origin: String) {
        var values = preferences.dictionary(forKey: key(account: account, origin: origin)) ?? [:]
        values.removeValue(forKey: String(kind))
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
    var actionName: String {
        kind < 0 ? String(localized: "Account connection") : BrowserEventDescription.name(for: kind)
    }
}
