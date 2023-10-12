//
//  OpenLatestUpdateMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/07/2023.
//

import SwiftUI

struct OpenLatestUpdateMessage: View {
    @EnvironmentObject private var themes:Themes
    var action:(() -> Void)? = nil
    
    var body: some View {
        HStack {
            
            Text("This article has been updated", comment: "Message shown when there is a newer version available of an article")
        
            Button(String(localized: "Open latest", comment: "Button go to latest version of article")) { action?() }
                .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
            
        }
        .padding(.leading, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            action?()
        }
    }
}

struct OpenLatestUpdateMessage_Previews: PreviewProvider {
    static var previews: some View {
        OpenLatestUpdateMessage()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
