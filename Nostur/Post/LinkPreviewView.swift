//
//  LinkPreviewx.swift
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
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        Group {
            VStack(alignment:.leading, spacing:0) {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                if viewSize.width > 0 {
                    if let image = tags["image"] {
                        LazyImage(url: URL(string: image)) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                        .processors([.resize(width: viewSize.width)])
                        .pipeline(ImageProcessing.shared.linkPreview)
                    }
                    VStack(alignment:.leading, spacing:5) {
                        if let title = tags["title"] {
                            Text(title.htmlUnescape()).lineLimit(2)
                                .fontWeight(.bold)
                        }
                        else if let title = tags["fallback_title"] {
                            Text(title.htmlUnescape()).lineLimit(2)
                                .fontWeight(.bold)
                        }
                        if let description = tags["description"] {
                            Text(description.htmlUnescape()).lineLimit(3)
                                .font(.caption)
                        }
                        Text(url.absoluteString).lineLimit(2)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(10)
                }
            }
            .onPreferenceChange(SizePreferenceKey.self) { size in
                guard size.width > 0 else { return }
                print("🟣🟣🟣🟣🟣 LPV \(size.width) \(size.height) -- \(UIScreen.main.scale) ")
                viewSize = size
            }
            .background(Color("ListBackground"))
            .clipShape(RoundedRectangle(cornerRadius: 10.0))
        }
        .onTapGesture {
            UIApplication.shared.open(url)
        }
        .task {
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
        NavigationStack {
            //            let url = "https://open.spotify.com/track/5Tbpp3OLLClPJF8t1DmrFD"
            //            let url = "https://youtu.be/qItugh-fFgg"
            let url = "https://youtu.be/QU9kRF9tHPU"
            LinkPreviewView(url: URL(string: url)!)
                .padding()
        }
    }
}
