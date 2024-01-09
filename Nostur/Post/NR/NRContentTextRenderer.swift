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
    public var isPreview = false
    
    var body: some View {
        NRContentTextRendererInner(attributedStringWithPs: attributedStringWithPs, isDetail: isDetail, isPreview: isPreview)
    }
}

struct NRContentTextRendererInner: View {
    public let attributedStringWithPs:AttributedStringWithPs
    public var isDetail = false
    public var isPreview = false
    
    @State private var height: CGFloat? = nil
    @State private var text: NSAttributedString? = nil
    @State private var previewText: AttributedString? = nil
    
    var body: some View {
        if isPreview, let previewOutput = attributedStringWithPs.previewOutput {
            Text(previewOutput)
                .lineSpacing(3)
                .lineLimit(isDetail ? 3000 : 20)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        else {
            if #available(iOS 16.0, *) {
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
                            if isPreview {
                                let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                                if self.previewText != reparsed.previewOutput {
                                    L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.previewOutput ?? "")")
                                    DispatchQueue.main.async {
                                        self.previewText = reparsed.previewOutput
                                    }
                                }
                            }
                            else {
                                let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                                if self.text != reparsed.output {
                                    L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                    DispatchQueue.main.async {
                                        self.text = reparsed.output
                                        self.height = reparsed.height
                                    }
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
                            if isPreview {
                                let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                                if self.previewText != reparsed.previewOutput {
                                    L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.previewOutput ?? "")")
                                    DispatchQueue.main.async {
                                        self.previewText = reparsed.previewOutput
                                    }
                                }
                            }
                            else {
                                let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                                if self.text != reparsed.output {
                                    L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                    DispatchQueue.main.async {
                                        self.text = reparsed.output
                                        self.height = reparsed.height
                                    }
                                }
                            }
                        }
                    }
                    .animation(.none)
            }
        }
    }
}
