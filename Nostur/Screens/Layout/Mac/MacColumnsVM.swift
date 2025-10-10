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
    
    @AppStorage("mac_list_state_serialized") var macListstateSerialized = ""
    @AppStorage("selected_tab") var selectedTab = "Main"
    
    static let shared = MacColumnsVM()
    
    @Published var columns: [ListID?] = []
    
    @MainActor
    public func addColumn() {
        guard allowAddColumn else { return }
        columns.append(nil)
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
    
    init() {
        let decoder = JSONDecoder()
        if let macListState = try? decoder.decode(MacListStateSerialized.self, from: macListstateSerialized.data(using: .utf8)!) {
            columns = macListState.columns
            L.og.debug("MacListState: restoring columns: \(self.columns.count) and list ids: \(self.columns.map { $0 == nil ? "nil" : $0! } .joined(separator: ", "))")
        }
        else {
            L.og.error("MacListState problem decoding macListstateSerialized")
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
    let columns: [String?]
}
