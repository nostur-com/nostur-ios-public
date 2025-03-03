//
//  Kind1063.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI
import NavigationBackport

struct Kind1063: View {
    
    @ObservedObject private var nrPost:NRPost
    private let url:String
    private let availableWidth:CGFloat
    private let fullWidth:Bool
    private var height:CGFloat? = nil
    private let forceAutoload:Bool
    private var theme:Theme
    @Binding var didStart: Bool
    
    init(_ nrPost:NRPost, fileMetadata:KindFileMetadata, availableWidth:CGFloat = .zero, fullWidth:Bool = false, forceAutoload: Bool = false, theme: Theme, didStart: Binding<Bool> = .constant(false)) {
        self.theme = theme
        self.nrPost = nrPost
        self.url = fileMetadata.url
        self.availableWidth = availableWidth
        self.fullWidth = fullWidth
        self.forceAutoload = forceAutoload
        _didStart = didStart
        if let dim = fileMetadata.dim {
            let dims = dim.split(separator: "x", maxSplits: 2)
            if dims.count == 2 {
                let width = (Double(dims[0]) ?? 1)
                let height = (Double(dims[1]) ?? 1)
                let widthPoints = width / UIScreen.main.scale
                let heightPoints = height / UIScreen.main.scale
                
                let ratio = widthPoints / heightPoints
                let scale = widthPoints / availableWidth
                
                let newHeight = (widthPoints / scale / ratio)
                
                if fullWidth {
                    self.height = newHeight
                }
                else {
                    self.height = min(DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, newHeight)
                }
            }
            else {
                self.height = DIMENSIONS.MAX_MEDIA_ROW_HEIGHT
            }
        }
        else {
            self.height = DIMENSIONS.MAX_MEDIA_ROW_HEIGHT
        }
    }
    
    private var shouldAutoload:Bool {
        forceAutoload || SettingsStore.shouldAutodownload(nrPost)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
                    
            }
            if is1063Video(nrPost) {
                EmbeddedVideoView(url: URL(string: url)!, pubkey: nrPost.pubkey, nrPost: nrPost, availableWidth: availableWidth + (fullWidth ? 20 : 0), autoload: shouldAutoload, theme: theme, didStart: $didStart)
                    .padding(.horizontal, fullWidth ? -10 : 0)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
//                    .withoutAnimation()
            }
            else if let height {
                SingleMediaViewer(url: URL(string: url)!, pubkey: nrPost.pubkey, imageWidth: availableWidth, fullWidth: fullWidth, autoload: shouldAutoload, theme: theme)
                    .padding(.horizontal, fullWidth ? -10 : 0)
//                    .padding(.horizontal, -10)
//                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: height)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

struct Kind1063_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadKind1063() }) {
            NBNavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") , let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}



func canRender1063(_ nrPost:NRPost) -> Bool {
    guard nrPost.kind == 1063 else { return false }
    guard let hl = nrPost.fileMetadata else { return false }
    
    guard let mTag = hl.m else { return false }
    guard !hl.url.isEmpty else { return false }
    guard ["video/mp4", "video/quicktime", "image/png", "image/jpg", "image/jpeg", "image/gif", "image/webp", "image/avif"].contains(mTag) else { return false }
    return true
}

func is1063Video(_ nrPost:NRPost) -> Bool {
    guard nrPost.kind == 1063 else { return false }
    guard let hl = nrPost.fileMetadata else { return false }
    
    guard let mTag = hl.m else { return false }
    guard !hl.url.isEmpty else { return false }
    guard ["video/mp4", "video/quicktime"].contains(mTag) else { return false }
    return true
}
