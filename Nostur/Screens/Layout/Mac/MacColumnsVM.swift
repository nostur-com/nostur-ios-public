//
//  MacListState.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI

public typealias ListID = String

class MacColumnsVM: ObservableObject {
    
    @AppStorage("mac_columns_serialized") var macListstateSerialized = ""
    
    @Published var selectedTab: String = "Main" {
        didSet {
            UserDefaults.standard.set(selectedTab, forKey: "selected_tab")
        }
    }
    
    @Published var selectedNotificationsTab: String = "Mentions" {
        didSet {
            UserDefaults.standard.set(selectedNotificationsTab, forKey: "selected_notifications_tab")
        }
    }
    
    static let shared = MacColumnsVM()
    
    private let defaults: UserDefaults
    private static let duoColumnCountKey = "duo_pro_column_count"
    @Published private(set) var duoColumnCount = 2

    var duoColumns: [MacColumnConfig] { Array(columns.prefix(duoColumnCount - 1)) }

    @MainActor
    func setDuoColumnCount(_ count: Int) {
        duoColumnCount = count >= 3 ? 3 : 2
        defaults.set(duoColumnCount, forKey: Self.duoColumnCountKey)
        prepareDuoColumns(defaultPhoneAccount: nil)
    }

    @MainActor
    func prepareDuoColumns(defaultPhoneAccount: String?) {
        let required = duoColumnCount - 1
        guard columns.count < required else { return }
        while columns.count < required {
            if columns.isEmpty, let defaultPhoneAccount {
                columns.append(MacColumnConfig(type: .notifications(defaultPhoneAccount)))
            }
            else {
                columns.append(MacColumnConfig())
            }
        }
        saveState()
    }

    @Published var columns: [MacColumnConfig] = []
    @Published var availableFeeds: [CloudFeed] = []
    
    @MainActor
    public func addColumn(_ config: MacColumnConfig? = nil) {
        guard allowAddColumn else { return }
        availableFeeds = getAvailableFeeds()
        if IS_IPHONE {
            prepareDuoColumns(defaultPhoneAccount: account()?.publicKey)
            if let config, columns.count > 1 {
                columns[1] = config
            }
            else if columns.count < 2 {
                columns.append(config ?? MacColumnConfig())
            }
            setDuoColumnCount(3)
            saveState()
            return
        }
        columns.append(config ?? MacColumnConfig())
        saveState()
    }
    
    /// Feed creation and "open in column" actions replace the last visible
    /// slot when full, without deleting hidden Duo configurations.
    @MainActor
    public func addOrReplaceColumn(_ config: MacColumnConfig) {
        if IS_IPHONE, duoColumnCount == 3 {
            availableFeeds = getAvailableFeeds()
            prepareDuoColumns(defaultPhoneAccount: nil)
            columns[1] = config
            saveState()
            return
        }
        if !allowAddColumn {
            columns.removeLast()
        }
        addColumn(config)
    }

    public var allowAddColumn: Bool {
        IS_IPHONE ? duoColumnCount < 3 : columns.count < 10
    }
    
    @MainActor
    public func removeColumn(_ id: String? = nil) {
        guard allowRemoveColumn else { return }
        if IS_IPHONE {
            setDuoColumnCount(2)
            return
        }
        _ = columns.removeLast()
        saveState()
    }
    
    public var allowRemoveColumn: Bool {
        IS_IPHONE ? duoColumnCount > 2 : columns.count > 0
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let storedCount = defaults.object(forKey: Self.duoColumnCountKey) as? Int {
            duoColumnCount = storedCount >= 3 ? 3 : 2
        }
        else if let data = defaults.string(forKey: "mac_columns_serialized")?.data(using: .utf8),
                let state = try? JSONDecoder().decode(MacListStateSerialized.self, from: data) {
            duoColumnCount = state.columns.count >= 2 ? 3 : 2
        }
        _macListstateSerialized = AppStorage(wrappedValue: "", "mac_columns_serialized", store: defaults)
        self.selectedTab = UserDefaults.standard.string(forKey: "selected_tab") ?? "Main"
        self.selectedNotificationsTab = UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions"
    }
    
    @MainActor
    public func load() async {
        // The folded phone shell can change these while Pro is inactive.
        selectedTab = UserDefaults.standard.string(forKey: "selected_tab") ?? "Main"
        selectedNotificationsTab = UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions"
        availableFeeds = getAvailableFeeds()
        restoreConfiguredColumns(defaultPhoneAccount: IS_IPHONE ? account()?.publicKey : nil)
        if IS_IPHONE {
            prepareDuoColumns(defaultPhoneAccount: account()?.publicKey)
        }
    }
    
    @MainActor
    func restoreConfiguredColumns(defaultPhoneAccount: String?) {
        // A saved empty array is intentional. Seed only a first-time phone setup.
        if macListstateSerialized.isEmpty, let defaultPhoneAccount {
            columns = [MacColumnConfig(type: .notifications(defaultPhoneAccount))]
            saveState()
            return
        }
        let decoder = JSONDecoder()
        if let data = macListstateSerialized.data(using: .utf8),
           let state = try? decoder.decode(MacListStateSerialized.self, from: data) {
            columns = state.columns
        }
        else {
            columns = []
        }
    }

    @MainActor
    private func getAvailableFeeds() -> [CloudFeed] {
        let activeAccount: CloudAccount? = account()
        
        return CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
            .filter {
                switch $0.feedType {
                    case .pubkeys(_):
                        return true
                    case .relays(_):
                        return true
                    case .followSet(_), .followPack(_):
                        return true
                    default:
                        return false
                }
            }
    }
    
    @MainActor
    public func updateColumn(_ config: MacColumnConfig) {
        // replace config in self.columns where config.id matches
        if let index = columns.firstIndex(where: { $0.id == config.id }) {
            self.objectWillChange.send()
            columns[index] = config
            saveState()
        }
    }
    
    public func saveState() {
        let state = MacListStateSerialized(columns: columns)
        let encoder = JSONEncoder()
        if let encodedState = try? encoder.encode(state) {
            macListstateSerialized = String(data: encodedState, encoding: .utf8) ?? ""
            L.og.debug("MacListState: saving state \(self.macListstateSerialized) -[LOG]-")
        }
        else {
            L.og.error("MacListState problem encoding macListstateSerialized")
        }
    }
}

struct MacListStateSerialized: Codable {
    let columns: [MacColumnConfig]
}

struct MacColumnConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var type: MacColumnType = .unconfigured
    var cloudFeedId: String? {
        if case .cloudFeed(let id) = type { return id }
        else { return nil }
    }
    var title: String?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.cloudFeedId == rhs.cloudFeedId && lhs.title == rhs.title
    }
}

struct DMConversationInfo: Codable, Equatable {
    let participants: Set<String>
    let ourAccountPubkey: String
}

enum MacColumnType: Codable, Equatable {
    case unconfigured
    case cloudFeed(String)
    
    case hot
    case zapped
    case emoji
    case articles // reads
    case gallery
    case discoverLists // lists & follow packs
    case streams // lists & follow packs
    case explore
    case search
    
    case notifications(String?) // .notifications(accountPubkey)
    case following(String) // .following(accountPubkey)
    case someoneElses(String) // .someoneElses(pubkey)
    case photos(String?) // .photos(accountPubkey)
    case yaks(String?) // .yaks(accountPubkey)
    case vines(String?) // .vines(accountPubkey)
    case mentions
    case bookmarks(Set<String>)
    case DMs(String?) // .DMs(accountPubkey)
    case DMConversation(DMConversationInfo)
    case newPosts
    
    var displayName: String {
        switch self {
        case .unconfigured:
            return "unconfigured"
        case .cloudFeed(let id):
            return "cloudFeed(\(id))"
        case .hot:
            return "hot"
        case .zapped:
            return "zapped"
        case .emoji:
            return "emoji"
        case .articles:
            return "articles"
        case .gallery:
            return "gallery"
        case .discoverLists:
            return "discoverLists"
        case .streams:
            return "streams"
        case .explore:
            return "explore"
        case .search:
            return "search"
        case .notifications(let accountPubkey):
            return "notifications(\(accountPubkey ?? "nil"))"
        case .following(let accountPubkey):
            return "following(\(accountPubkey)"
        case .someoneElses(let pubkey):
            return "someoneElses(\(pubkey)"
        case .photos(let accountPubkey):
            return "photos(\(accountPubkey ?? "nil"))"
        case .yaks(let accountPubkey):
            return "yaks(\(accountPubkey ?? "nil"))"
        case .vines(let accountPubkey):
            return "vines(\(accountPubkey ?? "nil"))"
        case .mentions:
            return "mentions"
        case .bookmarks(let filters):
            return "bookmarks(\(filters.sorted().joined(separator: ",")))"
        case .DMs(let accountPubkey):
            return "dms(\(accountPubkey ?? "nil"))"
        case .DMConversation(let dmConversationInfo):
            return "dmconversation(\(dmConversationInfo.participants.sorted().joined(separator: ",")))(\(dmConversationInfo.ourAccountPubkey)"
        case .newPosts:
            return "newPosts"
        }
    }
}

struct ActiveBookmarkFilters: Codable, Equatable {
    let filters: Set<String>
}


struct MacColumnsStateEnvironmentKey: EnvironmentKey {
    static let defaultValue: MacColumnsVM = .init()
}

extension EnvironmentValues {
    var macColumnsState: MacColumnsVM {
        get { self[MacColumnsStateEnvironmentKey.self] }
        set { self[MacColumnsStateEnvironmentKey.self] = newValue }
    }
}
