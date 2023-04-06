//
//  Centered.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//

import SwiftUI

struct CenteredProgressView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            Spacer()
        }
    }
}

struct Centered_Previews: PreviewProvider {
    static var previews: some View {
        CenteredProgressView()
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
