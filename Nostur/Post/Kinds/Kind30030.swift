//
//  Kind30030.swift
//  Nostur
//
//  Created by Codex on 15/04/2026.
//

import SwiftUI

struct Kind30030: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth

    private let nrPost: NRPost
    private let hideFooter: Bool
    private let missingReplyTo: Bool
    private var connect: ThreadConnectDirection? = nil
    private let isReply: Bool
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool

    private var title: String {
        (nrPost.eventTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? nrPost.dTag?.nilIfEmpty) ?? "Emoji set"
    }

    private var emojiItems: [EmojiSetItem] {
        var seen = Set<String>()
        var items: [EmojiSetItem] = []
        for tag in nrPost.fastTags where tag.0 == "emoji" {
            let shortcode = tag.1
            guard NIP30CustomEmoji.isValidShortcode(shortcode) else { continue }
            guard let urlString = tag.2, let url = URL(string: urlString) else { continue }
            let id = "\(shortcode)|\(url.absoluteString)"
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            items.append(EmojiSetItem(shortcode: shortcode, url: url))
        }
        return items
    }

    private var emojiColumns: [GridItem] {
        [GridItem(.adaptive(minimum: isEmbedded ? 84 : 92), spacing: 10)]
    }

    init(
        nrPost: NRPost,
        hideFooter: Bool = true,
        missingReplyTo: Bool = false,
        connect: ThreadConnectDirection? = nil,
        isReply: Bool = false,
        isDetail: Bool = false,
        isEmbedded: Bool = false,
        fullWidth: Bool,
        forceAutoload: Bool = false
    ) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.fullWidth = fullWidth
        self.forceAutoload = forceAutoload
    }

    var body: some View {
        if isEmbedded {
            embeddedView
        }
        else {
            normalView
        }
    }

    @ViewBuilder
    private var normalView: some View {
        PostLayout(
            nrPost: nrPost,
            hideFooter: hideFooter,
            missingReplyTo: missingReplyTo,
            connect: connect,
            isReply: isReply,
            isDetail: isDetail,
            fullWidth: fullWidth,
            forceAutoload: forceAutoload,
            nxViewingContext: nxViewingContext,
            containerID: containerID,
            theme: theme,
            availableWidth: availableWidth
        ) {
            content
        } title: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
                Text("\(emojiItems.count) emojis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, authorAtBottom: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .fontWeight(.bold)
                    .lineLimit(2)
                Text("\(emojiItems.count) emojis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if emojiItems.isEmpty {
            Text("No custom emoji tags found in this set.")
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
        else {
            LazyVGrid(columns: emojiColumns, spacing: 10) {
                ForEach(emojiItems) { item in
                    VStack(spacing: 6) {
                        NIP30EmojiImage(url: item.url, size: 30)
                        Text(":\(item.shortcode):")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .padding(.horizontal, 4)
                    .background(theme.secondaryBackground.cornerRadius(8))
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct EmojiSetItem: Identifiable {
    let shortcode: String
    let url: URL

    var id: String { "\(shortcode)|\(url.absoluteString)" }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
