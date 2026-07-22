//
//  VineVideoPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2026.
//

import SwiftUI

struct VineVideoPreview: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme

    let videoURL: URL
    let duration: Double
    let account: CloudAccount
    @ObservedObject var typingTextModel: TypingTextModel
    var onRemove: () -> Void

    @State private var isPlaying = true
    @State private var isMuted = false

    private var previewWidth: CGFloat {
        min(max(availableWidth - 48, 180), 280)
    }

    private var previewHeight: CGFloat {
        previewWidth * 16 / 9
    }

    var body: some View {
        ShortVideoPlayer(url: videoURL, isPlaying: $isPlaying, isMuted: $isMuted)
            .frame(width: previewWidth, height: previewHeight)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                removeButton
            }
            .overlay(alignment: .bottomLeading) {
                captionOverlay
            }
            .overlay(alignment: .bottomTrailing) {
                previewButtons
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .onTapGesture {
                isPlaying.toggle()
            }
            .frame(maxWidth: .infinity)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            isPlaying = false
            onRemove()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Remove video")
    }

    @ViewBuilder
    private var captionOverlay: some View {
        if !typingTextModel.text.isEmpty {
            Text(typingTextModel.text)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(10)
                .padding(.trailing, 46)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
        }
    }

    private var previewButtons: some View {
        VStack(alignment: .center, spacing: 8) {
            Spacer()
            previewButton(systemName: "ellipsis")
                .offset(x: -4)
                .padding(.bottom, 10)

            ObservedPFP(pubkey: account.publicKey, size: 30, forceFlat: true)
                .frame(width: 36, height: 36)
                .padding(.bottom, 12)

            previewButton(systemName: "bubble.left")
            previewButton(systemName: "arrow.2.squarepath")
            previewButton(systemName: "bolt.fill")
            previewButton(systemName: "bookmark")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.trailing, 10)
        .padding(.bottom, 10)
        .allowsHitTesting(false)
        .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
    }

    private func previewButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: 30, height: 30)
    }
}
