//
//  Kind1063.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct Kind1063: View {
    
    @ObservedObject var nrPost:NRPost
    let url:String
    let availableWidth:CGFloat
    let fullWidth:Bool
    var height:CGFloat? = nil
    
    init(_ nrPost:NRPost, fileMetadata:KindFileMetadata, availableWidth:CGFloat = .zero, fullWidth:Bool = false) {
        self.nrPost = nrPost
        self.url = fileMetadata.url
        self.availableWidth = availableWidth
        self.fullWidth = fullWidth
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
    
    var body: some View {
        VStack(alignment: .leading) {
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
                    
            }
            if let height {
                SingleMediaViewer(url: URL(string: url)!, pubkey: nrPost.pubkey, imageWidth: availableWidth, fullWidth: fullWidth, autoload: (nrPost.following || !SettingsStore.shared.restrictAutoDownload))
                    .padding(.horizontal, -10)
//                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: height)
                    .padding(.vertical, 10)
            }
        }
    }
}

struct Kind1063_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadKind1063() }) {
            NavigationStack {
                if let nrPost = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") , let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: UIScreen.main.bounds.width)
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
    guard ["image/png", "image/jpg", "image/jpeg", "image/gif", "image/webp"].contains(mTag) else { return false }
    return true
}
