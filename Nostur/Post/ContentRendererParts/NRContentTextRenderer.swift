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
        lhs.attributedStringWithPs.id == rhs.attributedStringWithPs.id &&
        lhs.isDetail == rhs.isDetail &&
        lhs.primaryColor == rhs.primaryColor &&
        lhs.accentColor == rhs.accentColor &&
        lhs.availableWidth == rhs.availableWidth
    }
    
    public let attributedStringWithPs: AttributedStringWithPs
    @Binding public var showMore: Bool
    public var availableWidth: CGFloat? = nil
    public var isDetail = false
    public var primaryColor: Color? = nil
    public var accentColor: Color? = nil
    public var onTap: (() -> Void)? = nil
    
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var dim: DIMENSIONS
    
    var body: some View {
        NRContentTextRendererInner(nxViewingContext: nxViewingContext, showMore: $showMore, attributedStringWithPs: attributedStringWithPs, availableWidth: availableWidth ?? dim.availableNoteRowWidth, isDetail: isDetail, primaryColor: primaryColor, accentColor: accentColor, onTap: onTap)
    }
}

let SELECTABLE_TEXT_CONTEXTS: Set<NXViewingContextOptions> = Set([.detailPane, .selectableText, .preview])

struct NRContentTextRendererInner: View {
    @Environment(\.theme) private var theme
    private let attributedStringWithPs: AttributedStringWithPs
    @Binding var showMore: Bool
    private let availableWidth: CGFloat
    private let isDetail: Bool
    private let primaryColor: Color
    private let accentColor: Color
    private let onTap: (() -> Void)?
    private let nxViewingContext: Set<NXViewingContextOptions>
    
    @State private var text: NSAttributedString?
    @State private var nxText: AttributedString?
    @State private var textWidth: CGFloat
    @State private var textHeight: CGFloat
    @State private var shouldShowMoreButton: Bool
    @State private var reparsedOutput: NSAttributedString? = nil
    @State private var reparsedNxOutput: AttributedString? = nil
    
    @EnvironmentObject private var dim: DIMENSIONS
    
    init(nxViewingContext: Set<NXViewingContextOptions>, showMore: Binding<Bool>, attributedStringWithPs: AttributedStringWithPs, availableWidth: CGFloat, isDetail: Bool = false, primaryColor: Color? = nil, accentColor: Color? = nil, onTap: (() -> Void)? = nil) {
        self.attributedStringWithPs = attributedStringWithPs
        _showMore = showMore
        self.availableWidth = availableWidth
        self.isDetail = isDetail
        self.primaryColor = primaryColor ?? Themes.default.theme.primary
        self.accentColor = accentColor ?? Themes.default.theme.accent
        self.onTap = onTap
        self.nxViewingContext = nxViewingContext
        
        _textWidth = State(wrappedValue: availableWidth)
        _textHeight = State(wrappedValue: 60)
        
        if nxViewingContext.isDisjoint(with: SELECTABLE_TEXT_CONTEXTS), let nxOutput = attributedStringWithPs.nxOutput { // Not selectable, but faster
            _nxText = State(wrappedValue: nxOutput)
//            _nxText = State(wrappedValue: nxOutput.prefix(NRTEXT_LIMIT)) // TODO: Reminder: also add back below reparsedNxOutput
            _shouldShowMoreButton = State(wrappedValue: false && !showMore.wrappedValue)
        }
        else if let output = attributedStringWithPs.output { // Use selectable for isDetail
            _text = State(wrappedValue: isDetail ? output : output.prefix(NRTEXT_LIMIT))
            _shouldShowMoreButton = State(wrappedValue: !showMore.wrappedValue && !isDetail && output.length > NRTEXT_LIMIT)
        }
        else if let nxOutput = attributedStringWithPs.nxOutput { // missing for some reason? fall back
            _nxText = State(wrappedValue: nxOutput)
            _shouldShowMoreButton = State(wrappedValue: false && !showMore.wrappedValue)
        }
        else {
            _text = State(wrappedValue: NSAttributedString(string: ""))
            _shouldShowMoreButton = State(wrappedValue: false && !showMore.wrappedValue)
        }
    }
    
    var body: some View {
        if let nxText {
            Text(nxText)
                .foregroundColor(primaryColor)
                .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    onTap?()
                }
            
                .onReceive(
                    ViewUpdates.shared.contactUpdated
                        .receive(on: RunLoop.main)
                        .filter { (pubkey, _) in
                            guard !attributedStringWithPs.input.isEmpty else { return false }
                            guard !attributedStringWithPs.pTags.isEmpty else { return false }
                            return self.attributedStringWithPs.pTags.contains(pubkey)
                        }
                ) { pubkey in
                    bg().perform {
                        guard let event = attributedStringWithPs.event else { return }
                        let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input, primaryColor: primaryColor)
                        guard let reparsedNxOutput = reparsed.nxOutput else { return }
//                        let output = isDetail ? reparsedNxOutput : reparsedNxOutput.prefix(NRTEXT_LIMIT)
                        if self.nxText != reparsedNxOutput {
#if DEBUG
                            L.og.debug("NRTextFixed.Reparsed: \(reparsed.input) ----> \(reparsedNxOutput)")
#endif
                            DispatchQueue.main.async {
                                self.nxText = reparsedNxOutput
                            }
                        }
                    }
                }
                .onChange(of: showMore) { [oldValue = self.showMore] newValue in
                    if newValue && !oldValue {
                        self.shouldShowMoreButton = false
                        if let nxOutput = reparsedNxOutput ?? attributedStringWithPs.nxOutput {
                            withAnimation {
                                self.nxText = nxOutput
                            }
                        }
                    }
                }
            
                .overlay(alignment: .bottomTrailing) {
                    if shouldShowMoreButton {
                        Text("Show more...")
                            .foregroundColor(.white)

                            .padding(5)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .foregroundColor(theme.accent)
                            }
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                showMore = true
                            })
                    }
                }
        }
        else if let text {
            if nxViewingContext.contains(.preview) {
                NRTextDynamic(text, fontColor: primaryColor, accentColor: accentColor)
                    .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            else if nxViewingContext.contains(.screenshot) {
                let aString = AttributedString(text)
                Text(aString)
                    .foregroundColor(primaryColor)
                    .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            else {
                if #available(iOS 16.0, *) { // because 15.0 doesn't have sizeThatFits(_ proposal: ProposedViewSize...
                    
                    NRTextFixed(text: text, fontColor: primaryColor, accentColor: accentColor, textWidth: $textWidth, textHeight: $textHeight, onTap: onTap)
                        .onReceive(
                            ViewUpdates.shared.contactUpdated
                                .receive(on: RunLoop.main)
                                .filter { (pubkey, _) in
                                    guard !attributedStringWithPs.input.isEmpty else { return false }
                                    guard !attributedStringWithPs.pTags.isEmpty else { return false }
                                    return self.attributedStringWithPs.pTags.contains(pubkey)
                                }
                        ) { pubkey in
                            bg().perform {
                                guard let event = attributedStringWithPs.event else { return }
                                let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input, primaryColor: primaryColor)
                                reparsedOutput = reparsed.output
                                guard let reparsedOutput else { return }
                                let output = isDetail || shouldShowMoreButton ? reparsedOutput : reparsedOutput.prefix(NRTEXT_LIMIT)
                                if self.text != output {
#if DEBUG
                                    L.og.debug("NRTextFixed.Reparsed: \(reparsed.input) ----> \(output)")
#endif
                                    DispatchQueue.main.async {
                                        self.text = output
                                    }
                                }
                            }
                        }
                        .frame(height: textHeight, alignment: .topLeading) // <-- Fixes clipped text height, stuck at initial 60, this problem only happens inside LazyVStack
                        .onChange(of: availableWidth) { newWidth in
                            guard newWidth != textWidth else { return }
                            textWidth = newWidth
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .onChange(of: showMore) { [oldValue = self.showMore] newValue in
                            if newValue && !oldValue {
                                self.shouldShowMoreButton = false
                                if let output = reparsedOutput ?? attributedStringWithPs.output {
                                    withAnimation {
                                        self.text = output
                                    }
                                }
                            }
                        }
                    
                        .overlay(alignment: .bottomTrailing) {
                            if shouldShowMoreButton {
                                Text("Show more...")
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 5)
                                            .foregroundColor(theme.accent)
                                    }
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(TapGesture().onEnded {
                                        showMore = true
                                    })
                            }
                        }
                }
                else {
                    NRTextDynamic(text, fontColor: primaryColor, accentColor: accentColor)
                        .onTapGesture {
                            onTap?()
                        }
                        .onReceive(
                            ViewUpdates.shared.contactUpdated
                                .receive(on: RunLoop.main)
                                .filter { (pubkey, _) in
                                    guard !attributedStringWithPs.input.isEmpty else { return false }
                                    guard !attributedStringWithPs.pTags.isEmpty else { return false }
                                    return self.attributedStringWithPs.pTags.contains(pubkey)
                                }
                        ) { pubkey in
                            bg().perform {
                                guard let event = attributedStringWithPs.event else { return }
                                let reparsed = NRTextParser.shared.parseText(fastTags: event.fastTags, event: event, text: attributedStringWithPs.input, primaryColor: primaryColor)
                                guard let reparsedOutput = reparsed.output else { return }
                                let output = isDetail || shouldShowMoreButton ? reparsedOutput : reparsedOutput.prefix(NRTEXT_LIMIT)
                                if self.text != output {
#if DEBUG
                                    L.og.debug("NRTextDynamic.Reparsed: \(reparsed.input) ----> \(output)")
#endif
                                    DispatchQueue.main.async {
                                        self.text = output
                                    }
                                }
                            }
                        }
                        .onChange(of: showMore) { [oldValue = self.showMore] newValue in
                            if newValue && !oldValue {
                                self.shouldShowMoreButton = false
                                if let output = reparsedOutput ?? attributedStringWithPs.output {
                                    withAnimation {
                                        self.text = output
                                    }
                                }
                            }
                        }
                    
                        .overlay(alignment: .bottomTrailing) {
                            if shouldShowMoreButton {
                                Text("Show more...")
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 5)
                                            .foregroundColor(theme.accent)
                                    }
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(TapGesture().onEnded {
                                        showMore = true
                                    })
                            }
                        }
                }
            }
        }
    }
}


let NRTEXT_LIMIT = IS_CATALYST ? 1600 : 800
