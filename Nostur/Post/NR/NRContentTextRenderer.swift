//
//  NRContentTextRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import SwiftUI

struct NRContentTextRenderer: View {
    @EnvironmentObject var theme:Theme
    let attributedStringWithPs:AttributedStringWithPs
    @State var text:AttributedString? = nil
    var isDetail = false
    
    var body: some View {
        Text(text ?? attributedStringWithPs.output)
//            .tint(theme.accent)
            .lineSpacing(3)
            .lineLimit(isDetail ? 3000 : 20)
            .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
            .frame(maxWidth: .infinity, alignment: .leading)    
            .onReceive(
                Importer.shared.contactSaved
                    .filter { pubkey in
                        guard !attributedStringWithPs.input.isEmpty else { return false }
                        guard !attributedStringWithPs.pTags.isEmpty else { return false }
                        return self.attributedStringWithPs.pTags.contains(pubkey)
                    }
                    .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            ) { pubkey in
                
                bg().perform {
                    let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                    DispatchQueue.main.async {
                        L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                        if self.text != reparsed.output {
                            self.text = reparsed.output
                        }
                    }
                }
            }
//            .transaction { t in
//                t.animation = nil
//            }
    }
}
