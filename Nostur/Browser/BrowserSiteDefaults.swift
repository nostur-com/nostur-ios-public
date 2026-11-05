import Foundation

/// Homepage apps share the same native defaults. Exact deployment aliases
/// identify those apps after redirects; no provider receives extra capabilities.
struct BrowserSiteDefaults: Equatable {
    let connected: Bool
    let social: Bool

    private static let homepage = Self(connected: true, social: true)
    static let unknown = Self(connected: false, social: false)

    /// Directory membership controls the initial site preferences.
    static func isHomepageApp(_ origin: String) -> Bool {
        let aliases = ["https://account.nostr.build": "https://nostr.build",
                       "https://app.flotilla.social": "https://flotilla.social",
                       "https://honey.hivetalk.org": "https://hivetalk.org"]
        let canonical = aliases[origin] ?? origin
        return BrowserDirectory.all.contains { BrowserSigningPolicy.origin($0.url) == canonical }
    }

    static func forOrigin(_ origin: String) -> Self {
        isHomepageApp(origin) ? homepage : unknown
    }
}
