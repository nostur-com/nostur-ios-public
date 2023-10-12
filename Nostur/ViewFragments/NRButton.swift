//
//  NRButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2023.
//

import SwiftUI

struct NRButtonStyle: ButtonStyle {
    var theme:Theme
    var style:Style = .default
    
    enum Style {
        case `default`
        case borderedProminent
    }
    
    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .default:
            configuration.label
                .foregroundColor(theme.accent)
        case .borderedProminent:
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.accent)
                .cornerRadius(5)
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
                    .buttonStyle(NRButtonStyle(theme: Themes.default.theme, style: .borderedProminent))
            }
                
                
        }
        .buttonStyle(NRButtonStyle(theme: Themes.default.theme))
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
