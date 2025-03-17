//
//  VideoEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/12/2023.
//

import SwiftUI
import NukeUI

struct VideoEventView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dim: DIMENSIONS
    
    public let title: String
    public let url: URL
    
    public var summary: String?
    public var imageUrl: URL?
    public var thumb: String?
    
    public var autoload: Bool = false
    
    public var theme: Theme
    
    public var availableWidth: CGFloat?
    
    var imageWidth: CGFloat {
        availableWidth ?? dim.availableNoteRowImageWidth()
    }
    
    static let aspect: CGFloat = 16/9
    
    var body: some View {
        if autoload {
            Group {
                VStack(alignment: .leading, spacing: 5) {
                    if let imageUrl {
                        MediaContentView(
                            galleryItem: GalleryItem(url: imageUrl),
                            availableWidth: imageWidth,
                            placeholderHeight: imageWidth * 9/16,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                            contentMode: .fit,
                            autoload: autoload
//                            tapUrl: url
                        )
                    }
                    else {
                        Image(systemName: "movieclapper")
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .foregroundColor(Color.gray)
                            .frame(width: DIMENSIONS.PREVIEW_HEIGHT * Self.aspect)
                            .onTapGesture {
                                openURL(url)
                            }
                    }
                    if #available(iOS 16.0, *) {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeight(.bold)
                            .padding(5)
                    }
                    else {
                        Text(title)
                            .lineLimit(2)
                            .layoutPriority(1)
                            .padding(5)
                    }
                    
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .lineLimit(30)
                            .font(.caption)
                            .padding(5)
                    }
                    
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(5)
//                            .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.listBackground)
            }
            .onTapGesture {
                openURL(url)
            }
        }
        else {
            Text(url.absoluteString)
                .foregroundColor(theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    openURL(url)
                }
        }
    }
}

#Preview {
    VideoEventView(title: "Categorias de Aristóteles", url: URL(string: "https://www.youtube.com/watch?v=je-n0Ro-B5k")!, summary: "", imageUrl: URL(string: "https://i3.ytimg.com/vi/je-n0Ro-B5k/hqdefault.jpg")!, autoload: true, theme: Themes.default.theme)
        .environmentObject(Themes.default)
        .environmentObject(DIMENSIONS.shared)
}
