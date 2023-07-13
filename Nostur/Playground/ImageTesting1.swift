//
//  ImageTesting1.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/05/2023.
//

import SwiftUI
import NukeUI

var TTToptions = {
    var TTToptions = ImageRequest.ThumbnailOptions(size: CGSize(width: 50, height: 50), unit: .points, contentMode: .aspectFill)
    TTToptions.createThumbnailFromImageAlways = true
    TTToptions.createThumbnailFromImageIfAbsent = true
    TTToptions.shouldCacheImmediately = true
    return TTToptions
}()

struct ImageTesting1: View {
    let testUrl = "https://nostur.com/nostur.png"
    @State var image:Image? = nil
    
//    var options = ImageRequest.ThumbnailOptions(size: CGSize(width: 50, height: 50), contentMode: .aspectFill)
    
    var body: some View {
        VStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipped()
            }
            
            Rectangle()
                .frame(width: 50, height: 50)
            
            LazyImage(request: ImageRequest(url: URL(string:testUrl)!, userInfo: [.thumbnailKey: TTToptions])) { state in
                if let cacheType = try? state.result?.get().cacheType {
                    if cacheType == .disk {
                        let _ = print("LazyImage: from disk")
                    }
                    else if cacheType == .memory {
                        let _ = print("LazyImage: from memory")
                    }
                }
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipped()
                }
            }
            .pipeline(ImageProcessing.shared.pfp)
            Button("P") {
                print(getCacheDirectoryPath())
                Task {
                    await self.test()
                }
            }
            Spacer()
        }
    }
    
    func test() async {
        
        let request = ImageRequest(url: URL(string:testUrl)!, userInfo: [.thumbnailKey: TTToptions])
        
        ImageProcessing.shared.pfp.loadImage(with: request) { result in
            if let cacheType = try? result.get().cacheType {
                if cacheType == .disk {
                    print("loadImage: from disk")
                }
                else if cacheType == .memory {
                    print("loadImage: from memory")
                }
            }
            else {
                print("loadImage: no cache")
            }
            if let image = try? result.get().container.image {
                self.image = Image(uiImage: image)
            }
        }
    }
    
}

func getCacheDirectoryPath() -> URL {
    let arrayPaths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    let cacheDirectoryPath = arrayPaths[0]
    return cacheDirectoryPath
}

struct ImageTesting1_Previews: PreviewProvider {
    static var previews: some View {
        ImageTesting1()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
