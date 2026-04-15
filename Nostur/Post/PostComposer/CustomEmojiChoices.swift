//
//  CustomEmojiChoices.swift
//  Nostur
//
//  Created by Codex on 15/04/2026.
//

import SwiftUI

struct ComposerCustomEmoji: Identifiable, Hashable {
    let shortcode: String
    let url: URL
    let pubkey: String
    let createdAt: Int64
    let setId: String
    let setTitle: String
    let setAuthor: String

    var id: String { Self.id(shortcode: shortcode, url: url) }

    static func id(shortcode: String, url: URL) -> String {
        "\(shortcode)|\(url.absoluteString)"
    }
}

struct CustomEmojiChoices: View {
    @ObservedObject var vm: NewPostModel
    @State private var largestEmojiBytesRendered: Int = 0

    private let columns = [
        GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 10)
    ]

    var body: some View {
        if vm.showCustomEmojiPicker {
            VStack(spacing: 0) {
                HStack {
                    Text("Choose custom emoji:")
                        .font(.caption)
                    Spacer()
                    HStack(spacing: 12) {
#if os(iOS) || targetEnvironment(macCatalyst)
                        Button {
                            hideKeyboard()
                        } label: {
                            Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                        }
                        .labelStyle(.iconOnly)
#endif
                        Button("Cancel", systemImage: "xmark") {
                            vm.dismissCustomEmojiPicker()
                        }
                        .labelStyle(.iconOnly)
                    }
                    .font(.body)
                }
                .padding(10)

                ScrollView {
                    if vm.isAutoFetchingInitialEmojiSets {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading emoji sets…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .padding(.horizontal, 12)
                    }
                    else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if vm.customEmojiShouldGroupResults {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(groupedResultSections, id: \.setId) { section in
                                        LazyVGrid(columns: columns, spacing: 10) {
                                            ForEach(section.items) { customEmoji in
                                                emojiButton(customEmoji)
                                            }
                                        }

                                        HStack(spacing: 6) {
                                            Spacer()
                                            Text("\(section.title) by")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            MiniPFP(pictureUrl: NRContact.instance(of: section.authorPubkey).pictureUrl, size: 16.0)
                                            Text(section.author)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                            else {
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(vm.customEmojiSearchResults) { customEmoji in
                                        emojiButton(customEmoji)
                                    }
                                }
                            }
                            
                            Button {
                                vm.findMoreEmojiSetsFromRelays()
                            } label: {
                                HStack(spacing: 8) {
                                    if vm.isFindingMoreEmojiSets {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text("Find more Emoji sets")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.isFindingMoreEmojiSets)
                            .padding(.top, 2)

                            Text("Largest emoji loaded: \(formattedByteCount(largestEmojiBytesRendered))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                        .padding([.top, .leading, .trailing])
                        .padding(.bottom, 6)
                    }
                }
            }
        }
    }

    private var groupedResultSections: [EmojiSetSection] {
        var order: [String] = []
        var grouped: [String: [ComposerCustomEmoji]] = [:]
        var sectionMeta: [String: (String, String, String)] = [:]

        for emoji in vm.customEmojiSearchResults {
            if grouped[emoji.setId] == nil {
                order.append(emoji.setId)
                sectionMeta[emoji.setId] = (emoji.setTitle, emoji.setAuthor, emoji.pubkey)
            }
            grouped[emoji.setId, default: []].append(emoji)
        }

        return order.compactMap { setId in
            guard let items = grouped[setId], let meta = sectionMeta[setId] else { return nil }
            return EmojiSetSection(setId: setId, title: meta.0, author: meta.1, authorPubkey: meta.2, items: items)
        }
    }

    @ViewBuilder
    private func emojiButton(_ customEmoji: ComposerCustomEmoji) -> some View {
        Button {
            vm.selectCustomEmoji(customEmoji)
        } label: {
            VStack(spacing: 6) {
                NIP30EmojiImage(url: customEmoji.url, size: 28) { bytes in
                    if bytes > largestEmojiBytesRendered {
                        largestEmojiBytesRendered = bytes
                    }
                }
                Text(":\(customEmoji.shortcode):")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private func formattedByteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func hideKeyboard() {
#if os(iOS) || targetEnvironment(macCatalyst)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}

private struct EmojiSetSection {
    let setId: String
    let title: String
    let author: String
    let authorPubkey: String
    let items: [ComposerCustomEmoji]
}
