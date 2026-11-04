import SwiftUI

struct BrowserDirectoryApp: Identifiable {
    let id: String
    let name: String
    let description: LocalizedStringKey
    let url: URL
    var keywords = ""
}

struct BrowserDirectorySection: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let icon: String
    let apps: [BrowserDirectoryApp]
    let keywords: String
}

enum BrowserDirectory {
    // Homepage entries share the defaults in BrowserSiteDefaults. Adding a link
    // grants those defaults; review the destination and any deployment aliases.
    // Keep descriptions factual and avoid prices or compatibility promises.
    static let sections: [BrowserDirectorySection] = [
        BrowserDirectorySection(id: "social", title: "Social", icon: "bubble.left.and.bubble.right", apps: [
            BrowserDirectoryApp(id: "jumble", name: "Jumble", description: "Conversations and relay feeds.", url: URL(string: "https://jumble.social")!, keywords: "posts relays"),
            BrowserDirectoryApp(id: "primal", name: "Primal", description: "People, posts and long-form reads.", url: URL(string: "https://primal.net")!, keywords: "posts articles"),
            BrowserDirectoryApp(id: "ditto", name: "Ditto", description: "A customizable social client from Soapbox.", url: URL(string: "https://ditto.pub")!, keywords: "themes posts soapbox"),
            BrowserDirectoryApp(id: "coracle", name: "Coracle", description: "Social feeds and relay exploration.", url: URL(string: "https://coracle.social")!, keywords: "relays posts"),
            BrowserDirectoryApp(id: "nostrmo", name: "Nostrmo", description: "A Nostr social client for the web.", url: URL(string: "https://web.nostrmo.com")!, keywords: "social posts"),
            BrowserDirectoryApp(id: "snort", name: "Snort", description: "A web client for conversations on Nostr.", url: URL(string: "https://snort.social")!, keywords: "posts")
        ], keywords: "social conversations posts"),
        BrowserDirectorySection(id: "reading", title: "Reading & writing", icon: "doc.text", apps: [
            BrowserDirectoryApp(id: "yakihonne", name: "YakiHonne", description: "Articles, notes and other Nostr content.", url: URL(string: "https://yakihonne.com")!, keywords: "articles publishing long form")
        ], keywords: "reading writing articles publishing"),
        BrowserDirectorySection(id: "media", title: "Photos & media", icon: "photo.on.rectangle", apps: [
            BrowserDirectoryApp(id: "nostr-build", name: "nostr.build", description: "Upload and manage photos, video and files.", url: URL(string: "https://nostr.build")!, keywords: "upload hosting storage blossom")
        ], keywords: "photos media video files uploads storage blossom"),
        BrowserDirectorySection(id: "streaming", title: "Live streams", icon: "play.rectangle", apps: [
            BrowserDirectoryApp(id: "zap-stream", name: "zap.stream", description: "Watch live streams from the Nostr community.", url: URL(string: "https://zap.stream")!, keywords: "live video music gaming"),
            BrowserDirectoryApp(id: "shosho", name: "Shosho", description: "Live streaming and creator channels.", url: URL(string: "https://shosho.live")!, keywords: "live video creators")
        ], keywords: "live streams streaming video"),
        BrowserDirectorySection(id: "communities", title: "Communities", icon: "person.3", apps: [
            BrowserDirectoryApp(id: "hivetalk", name: "HiveTalk", description: "Live conversations with the Nostr community.", url: URL(string: "https://hivetalk.org")!, keywords: "audio video rooms calls"),
            BrowserDirectoryApp(id: "flotilla", name: "Flotilla", description: "Community spaces, chat and events.", url: URL(string: "https://flotilla.social")!, keywords: "groups chat events")
        ], keywords: "communities groups chat events"),
        BrowserDirectorySection(id: "games", title: "Games", icon: "gamecontroller", apps: [
            BrowserDirectoryApp(id: "word5", name: "Word5", description: "A five-letter word puzzle with Nostr scores.", url: URL(string: "https://otherstuff.ai/word5/")!, keywords: "word puzzle game")
        ], keywords: "games puzzles"),
        BrowserDirectorySection(id: "relays", title: "Relay services", icon: "network", apps: [
            BrowserDirectoryApp(id: "nostr-wine", name: "nostr.wine", description: "Paid relay membership and related tools.", url: URL(string: "https://nostr.wine")!, keywords: "paid relay search"),
            BrowserDirectoryApp(id: "nostr-land", name: "nostr.land", description: "Relay aggregation, backups and account services.", url: URL(string: "https://nostr.land")!, keywords: "paid relay backup aggregation"),
            BrowserDirectoryApp(id: "nostr1", name: "nostr1.com / relay.tools", description: "Personal and community relay hosting.", url: URL(string: "https://nostr1.com")!, keywords: "hosting feeds relay tools"),
            BrowserDirectoryApp(id: "relay-tools-feeds", name: "Feeds by relay.tools", description: "Create and manage a hosted relay.", url: URL(string: "https://feeds.relay.tools")!, keywords: "hosting feeds personal community relay")
        ], keywords: "relays relay services hosting paid backups"),
        BrowserDirectorySection(id: "food", title: "Food & cooking", icon: "fork.knife", apps: [
            BrowserDirectoryApp(id: "zap-cooking", name: "zap.cooking", description: "Recipes, cooking stories and a food community.", url: URL(string: "https://zap.cooking")!, keywords: "food recipes cooking")
        ], keywords: "food cooking recipes")
    ]

    static let all = sections.flatMap(\.apps)
}
