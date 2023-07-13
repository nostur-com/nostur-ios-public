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

func randomColor(seed: String) -> Color {
    
    var total: Int = 0
    for u in seed.unicodeScalars {
        total += Int(UInt32(u))
    }
    
    srand48(total * 200)
    let r = CGFloat(drand48())
    
    srand48(total)
    let g = CGFloat(drand48())
    
    srand48(total / 200)
    let b = CGFloat(drand48())
    
    return Color(cgColor: CGColor(red: r, green: g, blue: b, alpha: 1.0))
}
