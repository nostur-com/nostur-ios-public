//
//  MinimalMediaThumbnail.swift
//  Nostur
//
//  Created by Claude on 10/06/2026.
//

import SwiftUI
import Nuke
import NukeUI

// Small thumbnail for notification rows (Reactions/Reposts/Zaps), so it's visible at a
// glance which media post a notification is about.
// Must stay passive: no gestures and no ZoomableItem here, the whole row is the tap target.
struct MinimalMediaThumbnail: View {
    @Environment(\.theme) private var theme
    public let url: URL
    public var extraCount: Int = 0 // shows "+N" badge when the post has more media than this thumbnail
    public var isVideo: Bool = false

    static let SIZE: CGFloat = 48.0

    var body: some View {
        theme.background
            .frame(width: Self.SIZE, height: Self.SIZE)
            .overlay {
                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.gray)
                }
                else {
                    LazyImage(
                        request: ImageRequest(
                            url: url,
                            processors: [.resize(size: CGSize(width: Self.SIZE, height: Self.SIZE), upscale: true)],
                            options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                            userInfo: [.scaleKey: UIScreen.main.scale]
                        )
                    ) { state in
                        if let image = state.image {
                            image
                        }
                        else {
                            Image(systemName: "photo")
                                .foregroundColor(Color.gray)
                        }
                    }
                    .pipeline(ImageProcessing.shared.content)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(3)
                }
            }
    }
}
