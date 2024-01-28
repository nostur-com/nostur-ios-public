//
//  BigLinkPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/01/2024.
//

import SwiftUI
import Nuke
import NukeUI
import HTMLEntities

struct BigLinkPreview: View {
    static let BIG_PREVIEW_IMAGE_HEIGHT: CGFloat = 350
    public let url: URL
    public var autoload:Bool = false
    public var theme:Theme
    @State var tags:[String: String] = [:]
    
    static let aspect:CGFloat = 16/9
    
    var body: some View {
        if autoload {
            Group {
                VStack(alignment: .leading, spacing: 5) {
                    if let image = tags["image"], image.prefix(7) != "http://" {
                        LazyImage(
                            request: ImageRequest(url: URL(string:image),
                                                  processors: [.resize(height: Self.BIG_PREVIEW_IMAGE_HEIGHT, upscale: false)],
                            options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                            userInfo: [.scaleKey: UIScreen.main.scale]), transaction: .init(animation: .none)) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                }
                        }
                        .pipeline(ImageProcessing.shared.content)
//                        .frame(width: (Self.BIG_PREVIEW_IMAGE_HEIGHT * Self.aspect))
                        .background(Color.gray)
//                        .clipped()
                    }
                    else {
                        Image(systemName: "link")
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 25)
                            .padding()
                            .foregroundColor(Color.gray)
//                            .frame(width: Self.BIG_PREVIEW_IMAGE_HEIGHT * Self.aspect)
                    }

                    
                    Group {
                        Text((tags["title"] ?? tags["fallback_title"]) ?? "")
                            .lineLimit(2)
                            .layoutPriority(1)
                            .fontWeightBold()
                            .padding(.top, 5)
                        
                        Text(tags["description"] ?? "")
                            .lineLimit(2)
                        
                        NRTextDynamic(url.absoluteString)
                            .padding(.top, 5)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 5)
                    }
                    .padding(.horizontal, 10)
                    
                }
                .background(theme.listBackground)
                .cornerRadius(10.0)
                .clipShape(RoundedRectangle(cornerRadius: 10.0))
            }
            .onTapGesture {
                UIApplication.shared.open(url)
            }
            .task {
                guard !SettingsStore.shared.lowDataMode else { return }
                guard url.absoluteString.prefix(7) != "http://" else { return }
                DispatchQueue.global().async {
                    if let tags = LinkPreviewCache.shared.cache.retrieveObject(at: url) {
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
                                LinkPreviewCache.shared.cache.setObject(for: url, value: tags)
                            }
                            catch {
                                
                            }
                        }
                    }
                }
            }
        }
        else {
            Text(url.absoluteString)
                .foregroundColor(theme.accent)
                .truncationMode(.middle)
                .onTapGesture {
                    UIApplication.shared.open(url)
                }
        }
    }
}

import NavigationBackport

struct BigLinkPreview_Previews: PreviewProvider {
    static var previews: some View {
        //            let url = "https://open.spotify.com/track/5Tbpp3OLLClPJF8t1DmrFD"
        //            let url = "https://youtu.be/qItugh-fFgg"
        let url = URL(string: "https://youtu.be/QU9kRF9tHPU")!
        let url2 = URL(string: "https://github.com/nostur-com/nids/blob/main/02.md")!
//        let url = URL(string:"https://nostur.com")!
        NBNavigationStack {
            VStack(alignment: .leading) {
                BigLinkPreview(url: url, theme: Themes.default.theme)
                    .padding(.vertical, 5)
                
                BigLinkPreview(url: url2, theme: Themes.default.theme)
                    .padding(.vertical, 5)
                
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(Themes.default)
    }
}
