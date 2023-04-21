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
    let imageWidth:CGFloat
    @State var tags:[String: String] = [:]
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        Group {
            VStack(alignment:.leading, spacing:0) {
                if let image = tags["image"] {
                    LazyImage(
                        request: ImageRequest(url: URL(string:image),
                        processors: [.resize(width: imageWidth, upscale: true)],
                        userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                            if let image = state.image { image }
                    }
                    .pipeline(ImageProcessing.shared.content)
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
            .background(Color("ListBackground"))
            .clipShape(RoundedRectangle(cornerRadius: 10.0))
            .padding(.horizontal, tags["image"] == nil ? 10 : 0)
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

struct LinkPreviewTest: View {
    @State var viewSize: CGSize = .zero
    
    var body: some View {
        //            let url = "https://open.spotify.com/track/5Tbpp3OLLClPJF8t1DmrFD"
        //            let url = "https://youtu.be/qItugh-fFgg"
        let url = "https://youtu.be/QU9kRF9tHPU"
        if viewSize.width > 0 {
            Text("what")
            LinkPreviewView(url: URL(string: url)!, imageWidth: viewSize.width)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
        }
        else {
            Text("whatdddd")
            Color.clear.frame(height: 0)
                .modifier(SizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    guard size.width > 0 else { return }
                    print("🟣🟣🟣🟣🟣 SINGLEMEDIA \(size.width) \(size.height) -- \(UIScreen.main.scale) ")
                    viewSize = size
                }
        }
    }
}

struct LinkPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LinkPreviewTest()
        }
    }
}
