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
        case theme
    }
    
    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .default:
            configuration.label
                .foregroundColor(theme.accent)

        case .borderedProminent:
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(theme.accent)
                .cornerRadius(25)
                .foregroundColor(Color.white)
            
        case .theme:
            configuration.label
                .background(theme.accent)
                .foregroundColor(Color.white)
        }
    }
}

#Preview {
    VStack {
        HStack {
            Button("Example") { }
                .buttonStyle(.borderedProminent)
            
            Button("Example") { }
                .buttonStyle(NRButtonStyle(style: .borderedProminent))
            
            Button { } label: {
                ProgressView().colorInvert()
            }
            .buttonStyleGlassProminent()
            
            Button { } label: {
                Label(String(localized: "Post.verb", comment: "Button to post (publish) a post"), systemImage: "paperplane.fill")
            }
            .buttonStyleGlassProminent()
        }
        
        HStack {
            Button { } label: {
                ProgressView().colorInvert()
            }
            .buttonStyleGlassProminentCircle()
            
            Button { } label: {
                Label(String(localized: "Post.verb", comment: "Button to post (publish) a post"), systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyleGlassProminentCircle()
        }
            
            
    }
    .buttonStyle(NRButtonStyle())
}
