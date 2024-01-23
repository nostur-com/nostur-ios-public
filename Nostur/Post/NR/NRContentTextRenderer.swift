//
//  NRContentTextRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import SwiftUI
import UIKit

// Trying out ..Inner and Equatable for performance maybe?
struct NRContentTextRenderer: View, Equatable {
    static func == (lhs: NRContentTextRenderer, rhs: NRContentTextRenderer) -> Bool {
        lhs.attributedStringWithPs.id == rhs.attributedStringWithPs.id
    }
    
    public let attributedStringWithPs: AttributedStringWithPs
    public var isDetail = false
    public var isScreenshot = false
    public var isPreview = false
    
    var body: some View {
        NRContentTextRendererInner(attributedStringWithPs: attributedStringWithPs, isDetail: isDetail, isScreenshot: isScreenshot, isPreview: isPreview)
    }
}

struct NRContentTextRendererInner: View {
    public let attributedStringWithPs:AttributedStringWithPs
    public var isDetail = false
    public var isScreenshot = false
    public var isPreview = false
    
    @State private var height: CGFloat? = nil
    @State private var text: NSAttributedString? = nil
    
    var body: some View {
        if isPreview {
            NRTextDynamic(text ?? attributedStringWithPs.output)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        else if isScreenshot {
            let aString = AttributedString(text ?? attributedStringWithPs.output)
            Text(aString)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        else {
            if #available(iOS 16.0, *) { // because 15.0 doesn't have sizeThatFits(_ proposal: ProposedViewSize...
                NRTextFixed(text ?? attributedStringWithPs.output, height: height ?? attributedStringWithPs.height)
                    .id(text ?? attributedStringWithPs.output)
//                    .debugDimensions("NRTextFixed")
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
                            guard let event = attributedStringWithPs.event else { return }
                            let reparsed = NRTextParser.shared.parseText(event, text: attributedStringWithPs.input)
                            if self.text != reparsed.output {
                                L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                DispatchQueue.main.async {
                                    self.text = reparsed.output
                                    self.height = reparsed.height
                                }
                            }
                        }
                    }
                    .animation(.none)
            }
            else {
                NRTextDynamic(text ?? attributedStringWithPs.output)
                    .id(text ?? attributedStringWithPs.output)
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
                            guard let event = attributedStringWithPs.event else { return }
                            let reparsed = NRTextParser.shared.parseText(event, text: attributedStringWithPs.input)
                            if self.text != reparsed.output {
                                L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                DispatchQueue.main.async {
                                    self.text = reparsed.output
                                    self.height = reparsed.height
                                }
                            }
                        }
                    }
                    .animation(.none)
            }
        }
    }
}
