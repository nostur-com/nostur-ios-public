//
//  LinkPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI
import LinkPresentation

struct LinkPreview : UIViewRepresentable {
    
    var url:URL
    var metadata:LPLinkMetadata?
    
//    @Binding var previewIsReady: Bool
    
    func makeUIView(context: Context) -> LPLinkView {
        if (metadata != nil) {
            let view = LPLinkView(url: url)
            view.metadata = metadata!
            return view
        }
        return LPLinkView(url: url)
    }
    
//    func makeUIView(context: Context) -> LPLinkView {
//
//        let metadata = LinkPreviewCache.shared.retrieveObject(at: url)
//        if (metadata != nil) {
//            let view = LPLinkView(metadata: metadata!)
////            view.sizeToFit()
//            return view
//        }
//
//        let view = LPLinkView(url: url)
//        let provider = LPMetadataProvider()
//
//
//        let (metadata, error) = await provider.startFetchingMetadata(for: url)
//
//        if let md = metadata {
//            LinkPreviewCache.shared.setObject(for: url, value: metadata!)
//            view.metadata = md
//            view.sizeToFit()
//            self.previewIsReady.toggle()
//        }
//
////        DispatchQueue.global(qos: .background).async {
////            provider.startFetchingMetadata(for: url) { (metadata, error) in
////                if let md = metadata {
//////                    LinkPreviewCache.shared.setObject(for: url, value: metadata!)
////                    DispatchQueue.main.async {
////                        view.metadata = md
////                        view.sizeToFit()
////                        self.previewIsReady.toggle()
////                    }
////                }
////
////            }
////        }
//
//        return view
//    }
    
    func updateUIView(_ uiView: LPLinkView, context: UIViewRepresentableContext<LinkPreview>) {
    }
}
