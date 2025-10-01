//
//  MacListState.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI

public typealias ListID = String

class MacListState: ObservableObject {
    
    @AppStorage("mac_list_state_serialized") var macListstateSerialized = ""
    @AppStorage("selected_tab") var selectedTab = "Main"
    
    static let shared = MacListState()
    
    var columnsCount:Int = 0 {
        didSet {
            saveState()
        }
    }
    var columns:[ListID] = []
    
    init() {
        let decoder = JSONDecoder()
        if let macListState = try? decoder.decode(MacListStateSerialized.self, from: macListstateSerialized.data(using: .utf8)!) {
            columnsCount = macListState.columnsCount
            columns = macListState.columns
            L.og.debug("MacListState: restoring columns: \(self.columnsCount) and list ids: \(self.columns.joined(separator: ", "))")
        }
        else {
            columnsCount = 1
            L.og.error("MacListState problem decoding macListstateSerialized")
        }
    }
    
    public func saveState() {
        let state = MacListStateSerialized(columnsCount: columnsCount, columns: columns)
        let encoder = JSONEncoder()
        if let encodedState = try? encoder.encode(state) {
            macListstateSerialized = String(data: encodedState, encoding: .utf8) ?? ""
            L.og.info("MacListState: saving state \(self.macListstateSerialized)")
        }
        else {
            L.og.error("MacListState problem encoding macListstateSerialized")
        }
    }
    
    struct MacListStateSerialized: Codable {
        let columnsCount:Int
        let columns:[String]
    }
    
}

