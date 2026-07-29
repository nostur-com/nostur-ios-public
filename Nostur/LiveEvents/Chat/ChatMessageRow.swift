//
//  ChatMessageRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2025.
//

import SwiftUI

struct ChatMessageRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @EnvironmentObject private var vc: ViewingContext
    @ObservedObject private var nrChat: NRChatMessage
    @ObservedObject private var nrContact: NRContact
    
    private let displayUserAgent: Bool
    private var zoomableId: String
    private let onReplyPreviewTap: (String) -> Void
    @Binding private var selectedContact: NRContact?
    
    init(
        nrChat: NRChatMessage,
        displayUserAgent: Bool,
        zoomableId: String = "Default",
        selectedContact: Binding<NRContact?>,
        onReplyPreviewTap: @escaping (String) -> Void = { _ in }
    ) {
        self.nrChat = nrChat
        self.nrContact = nrChat.nrContact
        self.displayUserAgent = displayUserAgent
        self.zoomableId = zoomableId
        self.onReplyPreviewTap = onReplyPreviewTap
        _selectedContact = selectedContact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                MiniPFP(pictureUrl: nrContact.pictureUrl)
                
                Text(nrContact.anyName)
                    .foregroundColor(theme.accent)

                Ago(nrChat.created_at).foregroundColor(theme.secondary)
                
                if displayUserAgent, let via = nrChat.via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded({ _ in
                selectedContact = nrContact
                if AnyPlayerModel.shared.viewMode == .detailstream {
                    AnyPlayerModel.shared.viewMode = .overlay
                }
                else if LiveKitVoiceSession.shared.visibleNest != nil {
                    LiveKitVoiceSession.shared.visibleNest = nil
                }
                
                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName), context: containerID)
            }))

            if let replyToId = nrChat.replyToId {
                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        guard nrChat.replyTo != nil else { return }
                        onReplyPreviewTap(replyToId)
                    } label: {
                        LiveChatReplyPreview(
                            parent: nrChat.replyTo,
                            resolution: nrChat.replyResolution
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(nrChat.replyTo == nil)
                    .accessibilityHint(nrChat.replyTo == nil ? "" : String(localized: "Jumps to the original message"))

                    renderedMessage(widthInset: 24)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(replyAccentColor.opacity(0.75))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                }
            }
            else {
                renderedMessage(widthInset: 10)
            }
        }
    }

    private func renderedMessage(widthInset: CGFloat) -> some View {
        ChatRenderer(nrChat: nrChat, availableWidth: min(600, vc.availableWidth) - widthInset, forceAutoload: false, zoomableId: zoomableId)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: 1800, alignment: .top)
            .clipped()
    }

    private var replyAccentColor: Color {
        nrChat.replyTo?.nrContact.randomColor ?? theme.accent
    }
}

private struct LiveChatReplyPreview: View {
    @Environment(\.theme) private var theme

    let parent: NRChatMessage?
    let resolution: NRChatMessage.ReplyResolution

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.caption.weight(.semibold))
                .foregroundColor(accentColor)

            if let parent {
                Text(parent.anyName)
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                    .lineLimit(1)
                    .layoutPriority(1)

                Text("·")
                    .foregroundColor(theme.secondary)

                if let attributedPreview = attributedPreviewText(for: parent) {
                    Text(attributedPreview)
                        .foregroundColor(theme.secondary)
                        .tint(theme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                else {
                    Text(fallbackPreviewText(for: parent))
                        .foregroundColor(theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            else {
                Text(resolution == .unavailable ? "Original message unavailable" : "Loading replied message…")
                .foregroundColor(theme.secondary)
                .lineLimit(1)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var accentColor: Color {
        parent?.nrContact.randomColor ?? theme.accent
    }

    private func attributedPreviewText(for parent: NRChatMessage) -> AttributedString? {
        for element in parent.contentElementsDetail {
            guard case .text(let attributedText) = element else { continue }
            if let nxOutput = attributedText.nxOutput {
                return nxOutput
            }
            if let output = attributedText.output {
                return AttributedString(output.string)
            }
        }
        return nil
    }

    private func fallbackPreviewText(for parent: NRChatMessage) -> String {
        if let content = parent.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        if parent.fileMessageInfo != nil {
            return String(localized: "File")
        }
        if !parent.galleryItems.isEmpty {
            return String(localized: "Media")
        }
        return String(localized: "Message")
    }
}
