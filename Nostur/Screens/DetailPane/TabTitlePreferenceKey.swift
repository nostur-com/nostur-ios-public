//
//  NosturTabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/06/2023.
//

import SwiftUI

struct TabTitlePreferenceKey: PreferenceKey {
    static let defaultValue: String = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
