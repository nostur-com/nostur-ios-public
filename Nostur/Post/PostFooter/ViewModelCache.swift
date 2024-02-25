//
//  ViewModelCache.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/10/2023.
//

import SwiftUI
import Algorithms

struct FooterButton: Identifiable {
    let id:String
    var isFirst:Bool = false
    var isLast:Bool = false
}

class ViewModelCache: ObservableObject {
    
    static let shared: ViewModelCache = ViewModelCache()
    
    private init() {
        footerButtons = SettingsStore.shared.footerButtons
    }
    
    static let MAX_BUTTONS: Int = 9 // Max 8 buttons on each row
    
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
    
    @Published var buttonRow: [FooterButton] = []
}
