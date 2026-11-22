import SwiftUI
import UIKit

/// A lightweight first-load surface that is already present when an adjacent
/// page is revealed. It does not instantiate posts or start feed requests.
struct FeedLoadingPreview<Title: View>: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    private let fullWidthOverride: Bool?
    private let title: Title
    private let message: String?

    init(message: String? = nil, fullWidth: Bool? = nil, @ViewBuilder title: () -> Title) {
        self.message = message
        self.fullWidthOverride = fullWidth
        self.title = title()
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    title
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    ProgressView()
                        .accessibilityLabel("Loading feed")
                }
                .padding(16)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                VStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        FeedLoadingPreviewRow(fullWidth: fullWidthOverride ?? settings.fullWidthImages,
                                              lineCount: [3, 2, 4, 2, 3][index],
                                              showFooter: settings.rowFooterEnabled,
                                              footerButtons: settings.footerButtons.map { String($0) })
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(theme.listBackground)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

private struct FeedLoadingPreviewRow: View {
    @Environment(\.theme) private var theme
    let fullWidth: Bool
    let lineCount: Int
    let showFooter: Bool
    let footerButtons: [String]

    var body: some View {
        // Use the same row insets, background and GUTTER as PostOrThread.
        Box(navMode: .noNavigation) {
            if fullWidth {
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        FeedLoadingAvatar()
                        FeedLoadingPostHeader(twoLines: true)
                    }
                    FeedLoadingPostContent(lineCount: lineCount, showFooter: showFooter, footerButtons: footerButtons)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    FeedLoadingAvatar()
                    VStack(alignment: .leading, spacing: 3) {
                        FeedLoadingPostHeader(twoLines: false)
                        FeedLoadingPostContent(lineCount: lineCount, showFooter: showFooter, footerButtons: footerButtons)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FeedLoadingAvatar: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Circle()
            .fill(theme.primary.opacity(0.1))
            .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
    }
}

private struct FeedLoadingPostHeader: View {
    @Environment(\.theme) private var theme
    let twoLines: Bool

    var body: some View {
        HStack(alignment: twoLines ? .center : .top) {
            if twoLines {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Author name").fontWeightBold()
                    Text(verbatim: "5m").font(.subheadline).foregroundStyle(.secondary)
                }
                .redacted(reason: .placeholder)
            } else {
                HStack(spacing: 5) {
                    Text(verbatim: "Author name").fontWeightBold()
                    Text(verbatim: "5m").font(.subheadline).foregroundStyle(.secondary)
                }
                .redacted(reason: .placeholder)
            }
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .fontWeightBold()
                .foregroundStyle(theme.footerButtons.opacity(0.3))
        }
        .lineLimit(1)
    }
}

private struct FeedLoadingPostContent: View {
    let lineCount: Int
    let showFooter: Bool
    let footerButtons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: String(repeating: "A preview of the post content.\n", count: lineCount - 1) + "More of the post")
                .font(Font(UIFont.nosturBody()))
                .lineLimit(lineCount)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .redacted(reason: .placeholder)
            if showFooter {
                FeedLoadingPostFooter(buttons: footerButtons)
            }
        }
        .padding(.bottom, showFooter ? 0 : 16)
    }
}

private struct FeedLoadingPostFooter: View {
    @Environment(\.theme) private var theme
    let buttons: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(buttons, id: \.self) { button in
                Group {
                    switch button {
                    case "💬": Image(systemName: "bubble.left")
                    case "🔄": Image(systemName: "arrow.2.squarepath")
                    case "+": Image(systemName: "heart")
                    case "⚡️", "⚡": Image(systemName: "bolt")
                    case "🔖": Image(systemName: "bookmark")
                    default: Text(verbatim: button)
                    }
                }
                .padding(.trailing, 30)
                .padding(.vertical, 5)
                if button != buttons.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(theme.footerButtons.opacity(0.3))
        .padding(.top, 5)
        .padding(.bottom, 16)
    }
}
