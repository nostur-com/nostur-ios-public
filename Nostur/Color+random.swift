//
//  Color+random.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//

import Foundation
import SwiftUI

extension Color {
    /// Return a random color
    static var random: Color {
        return Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
    
    static var randomUIColor: UIColor {
        return UIColor(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1),
            alpha: 1.0
        )
    }
    
    static var systemBackground: Color {
        Color(UIColor.systemBackground)
    }
}
