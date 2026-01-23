//
//  ViewModelCache.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/10/2023.
//

import SwiftUI
import Algorithms

struct FooterButton: Identifiable {
    let id: String
    var isFirst: Bool = false
    var isLast: Bool = false
}

class ViewModelCache: ObservableObject {
    
    static let shared: ViewModelCache = ViewModelCache()
    
    private init() {
        footerButtons = SettingsStore.shared.footerButtons
    }
    
    static let MAX_BUTTONS: Int = 9 // Max 9 buttons on each row
    
    public var footerButtons: String = "" {
        didSet {
            self.buttonRow = getButtonRow()
        }
    }
    
    private func getButtonRow() -> [FooterButton] {
        return self.footerButtons
            .map({ icon in // for each row, track first + last button for alignment
                FooterButton(
                    id: String(icon),
                    isFirst: self.footerButtons.first == icon,
                    isLast: self.footerButtons.last == icon
                )
            })
    }
    
    @Published var buttonRow: [FooterButton] = [] {
        didSet {
            // track custom reactions from button configurator
            // so when we do a custom emoji reaction it can be shown in EmojiButton if its not already a ReactionButton
            self.buttonIds = Set(buttonRow.map { $0.id })
                .subtracting(Set(["💬","🔄","⚡️","🔖"])) // but don't treat our own "special" ids as emoji
        }
    }
    
    // track custom reactions from button configurator
    // so when we do a custom emoji reaction it can be shown in EmojiButton if its not already a ReactionButton
    // but don't treat our own "special" ids as emoji
    public var buttonIds: Set<String> = []
}
