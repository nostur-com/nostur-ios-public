//
//  NRButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2023.
//

import SwiftUI

struct NRButtonStyle: ButtonStyle {
    @Environment(\.theme) var theme
    
    var style: Style = .default
    
    enum Style {
        case `default`
        case borderedProminent
    }
    
    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .default:
            configuration.label
                .foregroundColor(theme.accent)
//                .modifier {
//                    if let theme {
//                        $0.foregroundColor(theme.accent)
//                    }
//                    else {
//                        $0
//                    }
//                }
        case .borderedProminent:
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.accent)
//                .modifier {
//                    if let theme {
//                        $0.background(theme.accent)
//                    }
//                    else {
//                        $0
//                    }
//                }
                .cornerRadius(25)
                .foregroundColor(Color.white)
        }
    }
}

struct NRButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HStack {
                Button("Example") { }
                    .buttonStyle(.borderedProminent)
                
                Button("Example") { }
                    .buttonStyle(NRButtonStyle(style: .borderedProminent))
            }
                
                
        }
        .buttonStyle(NRButtonStyle())
    }
}
