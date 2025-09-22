//
//  Helpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/09/2025.
//

import Foundation

func selectedTab() -> String {
    UserDefaults.standard.string(forKey: "selected_tab") ?? "Main"
}
