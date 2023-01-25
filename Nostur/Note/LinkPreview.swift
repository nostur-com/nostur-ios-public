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
    
    @Binding var togglePreview: Bool
    
    func makeUIView(context: Context) -> LPLinkView {
        
        let metadata = LinkPreviewCache.shared.retrieveObject(at: url)
        if (metadata != nil) {
            let view = LPLinkView(metadata: metadata!)
            view.sizeToFit()
            return view
        }
        
        let view = LPLinkView(url: url)
        let provider = LPMetadataProvider()
        
        DispatchQueue.global(qos: .userInitiated).async {
            provider.startFetchingMetadata(for: url) { (metadata, error) in
                if let md = metadata {
                    LinkPreviewCache.shared.setObject(for: url, value: metadata!)
                    DispatchQueue.main.async {
                        view.metadata = md
                        view.sizeToFit()
                        self.togglePreview.toggle()
                    }
                }
                
            }
        }
        //        DispatchQueue(label: "fetchUrlPreview", qos: .background, attributes: .concurrent).async {
        //
        //            provider.startFetchingMetadata(for: url) { (metadata, error) in
        //                if let md = metadata {
        //
        //                    LinkPreviewCache.shared.setObject(for: url, value: metadata!)
        //
        //                    DispatchQueue.main.async {
        //                        view.metadata = md
        //                        view.sizeToFit()
        //                        self.togglePreview.toggle()
        //                    }
        //                }
        //            }
        //
        //        }
        
        return view
    }
    
    func updateUIView(_ uiView: LPLinkView, context: UIViewRepresentableContext<LinkPreview>) {
    }
}
