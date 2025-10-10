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
    @AppStorage("selected_tab") var selectedTab = "Main"
    
    static let shared = MacColumnsVM()
    
    @Published var columns: [MacColumnConfig] = []
    @Published var availableFeeds: [CloudFeed] = []
    
    @MainActor
    public func addColumn() {
        guard allowAddColumn else { return }
        columns.append(MacColumnConfig())
        saveState()
    }
    
    public var allowAddColumn: Bool {
        columns.count < 10
    }
    
    @MainActor
    public func removeColumn(_ id: String? = nil) {
        guard allowRemoveColumn else { return }
        _ = columns.removeLast()
        saveState()
    }
    
    public var allowRemoveColumn: Bool {
        columns.count > 0
    }
    
    init() {}
    
    @MainActor
    public func load() async {
        availableFeeds = await getAvailableFeeds()
        columns = await getConfiguredColumns()
    }
    
    @MainActor
    private func getConfiguredColumns() async -> [MacColumnConfig] {
        let decoder = JSONDecoder()
        if let macListState = try? decoder.decode(MacListStateSerialized.self, from: macListstateSerialized.data(using: .utf8)!) {
            L.og.debug("MacListState: restoring columns: \(macListState.columns.count) and list ids: \(macListState.columns.map { $0.type.rawValue } .joined(separator: ", "))")
      
            return macListState.columns
        }
        else {
            L.og.error("MacListState problem decoding macListstateSerialized")
            return []
        }
    }
    
    @MainActor
    private func getAvailableFeeds() async -> [CloudFeed] {
        return CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
            .filter {
                switch $0.feedType {
                    case .picture(_):
                        return true
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
            L.og.info("MacListState: saving state \(self.macListstateSerialized)")
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
    var cloudFeedId: String?
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.cloudFeedId == rhs.cloudFeedId
    }
}

enum MacColumnType: String, Codable {
    case unconfigured
    case cloudFeed
    case notifications
    case following
    case photos
    case mentions
    case bookmarks
    case DMs
    case newPosts
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
