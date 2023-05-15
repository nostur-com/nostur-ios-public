//
//  NRContentTextRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import SwiftUI

struct NRContentTextRenderer: View {
    
    let attributedStringWithPs:AttributedStringWithPs
    let fullWidth = false
    @State var text:AttributedString? = nil
    
    var body: some View {
        Text(text ?? attributedStringWithPs.output)
            .textSelection(.enabled)
            .multilineTextAlignment(TextAlignment.leading)
            .foregroundColor(.primary)
            .accentColor(Color("AccentColor"))
            .tint(Color("AccentColor"))
            .lineSpacing(3)
            .padding(.horizontal, fullWidth ? 10 : 0)
            .onReceive(
                receiveNotification(.contactSaved)
                    .map({ notification in
                        return notification.object as! String
                    })
                    .filter({ pubkey in
                        guard !attributedStringWithPs.input.isEmpty else { return false }
                        guard attributedStringWithPs.pTags.count > 0 else { return false }
                        return self.attributedStringWithPs.pTags.contains(pubkey)
                    })
                    .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            ) { pubkey in
                
                DataProvider.shared().bg.perform {
                    let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                    DispatchQueue.main.async {
                        print("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                        if self.text != reparsed.output {
                            self.text = reparsed.output
                        }
                    }
                }
            }
    }
}
//
//struct NRContentTextRenderer_Previews: PreviewProvider {
//    static var previews: some View {
//        NRContentTextRenderer()
//    }
//}
