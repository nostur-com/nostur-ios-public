//
//  LinkPreviewView.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/04/2023.
//

import SwiftUI
import Nuke
import NukeUI
import HTMLEntities

struct LinkPreviewView: View {
    let url:URL
    @State var tags:[String: String] = [:]
    
    var body: some View {
        Group {
            HStack(alignment: .center, spacing:0) {
                if let image = tags["image"], image.prefix(7) != "http://" {
                    LazyImage(
                        request: ImageRequest(url: URL(string:image),
                                              processors: [.resize(height: DIMENSIONS.PREVIEW_HEIGHT, upscale: true)],
                        userInfo: [.scaleKey: UIScreen.main.scale]), transaction: .init(animation: .none)) { state in
                            if let image = state.image {
                                image.interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: (DIMENSIONS.PREVIEW_HEIGHT * 2))
                            }
                    }
                    .pipeline(ImageProcessing.shared.content)
                }
                VStack(alignment:.leading, spacing:0) {
                    if let title = tags["title"] {
                        Text(title).lineLimit(1)
                            .fontWeight(.bold)
                    }
                    else if let title = tags["fallback_title"] {
                        Text(title).lineLimit(1)
                            .fontWeight(.bold)
                    }
                    if let description = tags["description"] {
                        Text(description).lineLimit(2)
                            .font(.caption)
                    }
                    Text(url.absoluteString).lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(5)
                .frame(height: DIMENSIONS.PREVIEW_HEIGHT)

            }
            .background(Color("ListBackground"))
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: DIMENSIONS.PREVIEW_HEIGHT)
            .clipShape(RoundedRectangle(cornerRadius: 10.0))
        }
        .onTapGesture {
            UIApplication.shared.open(url)
        }
        .task {
            guard url.absoluteString.prefix(7) != "http://" else { return }
            if let tags = LinkPreviewCache.shared.retrieveObject(at: url) {
                self.tags = tags
            }
            else {
                fetchMetaTags(url: url) { result in
                    do {
                        self.tags = try result.get()
                        LinkPreviewCache.shared.setObject(for: url, value: self.tags)
                    }
                    catch {
                        
                    }
                }
            }
        }
    }
}

struct LinkPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        //            let url = "https://open.spotify.com/track/5Tbpp3OLLClPJF8t1DmrFD"
        //            let url = "https://youtu.be/qItugh-fFgg"
        let url = URL(string:"https://youtu.be/QU9kRF9tHPU")!
//        let url = URL(string:"https://nostur.com")!
        NavigationStack {
            LinkPreviewView(url: url)
                .padding(.vertical, 5)
        }
    }
}
