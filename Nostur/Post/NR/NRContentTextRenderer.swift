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
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding(.horizontal, fullWidth ? 10 : 0)
            .onReceive(
                receiveNotification(.contactSaved)
                    .map({ notification in
                        return notification.object as! String
                    })
                    .filter({ pubkey in
                        guard !attributedStringWithPs.input.isEmpty else { return false }
                        guard !attributedStringWithPs.pTags.isEmpty else { return false }
                        return self.attributedStringWithPs.pTags.contains(pubkey)
                    })
                    .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            ) { pubkey in
                
                DataProvider.shared().bg.perform {
                    let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                    DispatchQueue.main.async {
                        L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                        if self.text != reparsed.output {
                            self.text = reparsed.output
                        }
                    }
                }
            }
    }
}
