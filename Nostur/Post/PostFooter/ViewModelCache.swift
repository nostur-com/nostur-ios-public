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

struct ButtonRow: Identifiable {
    let id:UUID
    let buttons:[FooterButton]
}

class ViewModelCache: ObservableObject {
    
    static let shared:ViewModelCache = ViewModelCache()
    
    private init() {
        footerButtons = SettingsStore.shared.footerButtons
    }
    
    static let BUTTONS_PER_ROW:Int = 9 // Max 8 buttons on each row
    
    private var rows:Int {
        Int(ceil(Double(footerButtons.count) / Double(ViewModelCache.BUTTONS_PER_ROW)))
    }
    public var footerButtons:String = "" {
        didSet {
            self.buttonRows = getButtonRows()
        }
    }
    
    private func getButtonRows() -> [ButtonRow] {
        return Array(self.footerButtons) // String to [Character]
            .chunks(ofCount: ViewModelCache.BUTTONS_PER_ROW).map(Array.init) // to rows of buttons [[Character], [Character], ...]
            .map({ icons in
                icons.map({ icon in // for each row, track first + last button for alignment
                    FooterButton(
                        id: String(icon),
                        isFirst: icons.first == icon,
                        isLast: icons.last == icon
                    )
                })
            })
            .map({ ButtonRow(id: UUID(), buttons: $0) })
    }
    
    @Published var buttonRows:[ButtonRow] = []
}
