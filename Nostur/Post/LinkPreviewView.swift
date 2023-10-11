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
    @EnvironmentObject var theme:Theme
    let url:URL
    @State var tags:[String: String] = [:]
    
    static let aspect:CGFloat = 16/9
    
    var body: some View {
        Group {
            HStack(alignment: .center, spacing: 5) {
                if let image = tags["image"], image.prefix(7) != "http://" {
                    LazyImage(
                        request: ImageRequest(url: URL(string:image),
                                              processors: [.resize(size: CGSize(width:DIMENSIONS.PREVIEW_HEIGHT * Self.aspect, height:DIMENSIONS.PREVIEW_HEIGHT), upscale: true)],
                        options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                        userInfo: [.scaleKey: UIScreen.main.scale]), transaction: .init(animation: .none)) { state in
                            if let image = state.image {
                                image.interpolation(.none)
                            }
                    }
                    .pipeline(ImageProcessing.shared.content)
                    .frame(width: (DIMENSIONS.PREVIEW_HEIGHT * Self.aspect))
                    .background(Color.gray)
                    .clipped()
                }
                else {
                    Image(systemName: "link")
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .foregroundColor(Color.gray)
                        .frame(width: DIMENSIONS.PREVIEW_HEIGHT * Self.aspect)
                }
                VStack(alignment:.leading, spacing: 0) {
                    Text((tags["title"] ?? tags["fallback_title"]) ?? "")
                        .lineLimit(2)
                        .layoutPriority(1)
                        .fontWeight(.bold)
                    
                    Text(tags["description"] ?? "")
                        .lineLimit(2)
                        .font(.caption)
                    
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(5)
                .minimumScaleFactor(0.7)
//                .frame(height: DIMENSIONS.PREVIEW_HEIGHT)
            }
            .background(theme.listBackground)
            .frame(height: DIMENSIONS.PREVIEW_HEIGHT)
            .clipShape(RoundedRectangle(cornerRadius: 10.0))
        }
        .onTapGesture {
            UIApplication.shared.open(url)
        }
        .task {
            guard !SettingsStore.shared.lowDataMode else { return }
            guard url.absoluteString.prefix(7) != "http://" else { return }
            DispatchQueue.global().async {
                if let tags = LinkPreviewCache.shared.retrieveObject(at: url) {
                    DispatchQueue.main.async {
                        self.tags = tags
                    }
                }
                else {
                    fetchMetaTags(url: url) { result in
                        do {
                            let tags = try result.get()
                            DispatchQueue.main.async {
                                self.tags = tags
                            }
                            LinkPreviewCache.shared.setObject(for: url, value: tags)
                        }
                        catch {
                            
                        }
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
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(Theme.default)
    }
}
