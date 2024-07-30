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
    public var availableWidth: CGFloat? = nil
    public var isScreenshot = false
    public var isPreview = false
    public var primaryColor: Color? = nil
    public var accentColor: Color? = nil
    
    @EnvironmentObject private var dim: DIMENSIONS
    
    var body: some View {
        NRContentTextRendererInner(attributedStringWithPs: attributedStringWithPs, availableWidth: availableWidth ?? dim.availableNoteRowWidth, isScreenshot: isScreenshot, isPreview: isPreview, primaryColor: primaryColor, accentColor: accentColor)
    }
}

struct NRContentTextRendererInner: View {
    private let attributedStringWithPs: AttributedStringWithPs
    private let availableWidth: CGFloat
    private let isScreenshot: Bool
    private let isPreview: Bool
    private let primaryColor: Color?
    private let accentColor: Color?

    @State private var text: NSAttributedString? = nil
    @State private var textWidth: CGFloat
    @State private var textHeight: CGFloat
    
    @EnvironmentObject private var dim: DIMENSIONS
    
    init(attributedStringWithPs: AttributedStringWithPs, availableWidth: CGFloat, isScreenshot: Bool = false, isPreview: Bool = false, primaryColor: Color? = nil, accentColor: Color? = nil) {
        self.attributedStringWithPs = attributedStringWithPs
        self.availableWidth = availableWidth
        self.isScreenshot = isScreenshot
        self.isPreview = isPreview
        self.primaryColor = primaryColor
        self.accentColor = accentColor
        _textWidth = State(wrappedValue: availableWidth)
        _textHeight = State(wrappedValue: 60)
    }
    
    var body: some View {
        if isPreview {
            NRTextDynamic(text ?? attributedStringWithPs.output, fontColor: primaryColor ?? Themes.default.theme.primary, accentColor: accentColor)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        else if isScreenshot {
            let aString = AttributedString(text ?? attributedStringWithPs.output)
            Text(aString)
                .foregroundColor(primaryColor ?? Themes.default.theme.primary)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        else {
            if #available(iOS 16.0, *) { // because 15.0 doesn't have sizeThatFits(_ proposal: ProposedViewSize...
//                Color.red.frame(height: 30)
//                    .debugDimensions(alignment: .topLeading)
//                Color.clear
//                    .overlay(alignment: .topLeading) {
//                        
//                    }
                
                NRTextFixed(text ?? attributedStringWithPs.output, fontColor: primaryColor ?? Themes.default.theme.primary, accentColor: accentColor, textWidth: $textWidth, textHeight: $textHeight)
//                    .background(Color.red.opacity(0.2))
  
//                    .overlay(alignment: .topLeading) {
//                        Text("\(textWidth.rounded().description)x\(textHeight.rounded().description)")
//                            .background(Color.black)
//                            .foregroundColor(.white)
//                    }
                    .id(text ?? attributedStringWithPs.output)
                    .onReceive(receiveNotification(.dynamicTextChanged)) { _ in
                        bg().perform {
                            guard !attributedStringWithPs.input.isEmpty else { return }
                            guard let event = attributedStringWithPs.event else { return }
                            let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input)
                            let textHeight = reparsed.output.boundingRect(
                                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                context: nil
                            ).height
                            if self.textHeight != textHeight {
//                                L.og.debug("⧢⧢ Reparsed after .dynamicTextChanged: \(self.textHeight) ----> \(textHeight) \(attributedStringWithPs.input.prefix(25))")
                                DispatchQueue.main.async {
                                    self.textHeight = textHeight
//                                    self.text = reparsed.output
                                }
                            }
                        }
                    }
                    .onReceive(
                        Importer.shared.contactSaved
                            .receive(on: RunLoop.main)
                            .filter { pubkey in
                                guard !attributedStringWithPs.input.isEmpty else { return false }
                                guard !attributedStringWithPs.pTags.isEmpty else { return false }
                                return self.attributedStringWithPs.pTags.contains(pubkey)
                            }
//                            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
                    ) { pubkey in
                        bg().perform {
                            guard let event = attributedStringWithPs.event else { return }
                            let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input)
                            if self.text != reparsed.output {
//                                L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                DispatchQueue.main.async {
                                    self.text = reparsed.output
                                }
                            }
                        }
                    }
                    .transaction { t in t.animation = nil } // <-- needed or not?
                    .frame(height: textHeight, alignment: .topLeading)
//                    .fixedSize(horizontal: false, vertical: true) // needed or text height stays at inital textHeight (90)
                    .onChange(of: availableWidth) { newWidth in
                        guard newWidth != textWidth else { return }
                        textWidth = newWidth
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            else {
                NRTextDynamic(text ?? attributedStringWithPs.output, fontColor: primaryColor ?? Themes.default.theme.primary, accentColor: accentColor)
                    .id(text ?? attributedStringWithPs.output)
                    .onReceive(
                        Importer.shared.contactSaved
                            .receive(on: RunLoop.main)
                            .filter { pubkey in
                                guard !attributedStringWithPs.input.isEmpty else { return false }
                                guard !attributedStringWithPs.pTags.isEmpty else { return false }
                                return self.attributedStringWithPs.pTags.contains(pubkey)
                            }
//                            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
                    ) { pubkey in
                        bg().perform {
                            guard let event = attributedStringWithPs.event else { return }
                            let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input)
                            if self.text != reparsed.output {
                                L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                                DispatchQueue.main.async {
                                    self.text = reparsed.output
                                }
                            }
                        }
                    }
                    .transaction { t in t.animation = nil }
            }
        }
    }
}
