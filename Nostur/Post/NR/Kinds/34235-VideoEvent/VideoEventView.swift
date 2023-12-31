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
    
    public var autoload:Bool = false
    
    public var theme: Theme
    
    public var availableWidth: CGFloat?
    
    static let aspect: CGFloat = 16/9
    
    var body: some View {
        if autoload {
            Group {
                VStack(alignment: .leading, spacing: 5) {
                    if let imageUrl {
                        SingleMediaViewer(url: imageUrl, pubkey: "", imageWidth: availableWidth ?? dim.availableNoteRowImageWidth(), fullWidth: true, autoload: autoload, contentPadding: 0, contentMode: .aspectFit, upscale: true, theme: theme, tapUrl: url)
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
                    Text(title)
                        .lineLimit(2)
                        .layoutPriority(1)
                        .fontWeight(.bold)
                        .padding(5)
                    
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
