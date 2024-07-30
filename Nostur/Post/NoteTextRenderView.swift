//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI

// Was before for just rendering embedded (text) posts, but does other kinds too now, should rename.
struct NoteTextRenderView: View {
    @EnvironmentObject private var dim: DIMENSIONS
    public let nrPost: NRPost
    public var forceAutoload = false
    public var theme: Theme
    @State private var didStart = false
    
    private var shouldAutoload: Bool {
        forceAutoload || SettingsStore.shouldAutodownload(nrPost)
    }
    
    var body: some View {
        if canRender1063(nrPost), let fileMetadata = nrPost.fileMetadata {
            Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: dim.availableNoteRowImageWidth(), forceAutoload: shouldAutoload, theme: theme)
        }
        else {
            switch nrPost.kind {
            case 9802:
                HighlightRenderer(nrPost: nrPost, theme: theme)
                
            case 443:
                URLView(nrPost: nrPost, theme: theme)
                    .navigationTitle("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                
            case 9735:
                if let zap = nrPost.mainEvent, let zapFrom = zap.zapFromRequest {
                    ZapReceipt(sats: zap.naiveSats, receiptPubkey: zap.pubkey, fromPubkey: zapFrom.pubkey, from: zapFrom)
                }
                
            case 0,3,4,5,7,1984,9734,30009,8,30008:
                KnownKindView(nrPost: nrPost, hideFooter: true, theme: theme)
                
            case 1,6,30023,99999:
//                Color.red.frame(height: 30)
//                    .debugDimensions("spacer")
//                Text(dim.availablePostDetailImageWidth().description)
                ContentRenderer(nrPost: nrPost, isDetail: false, availableWidth: dim.listWidth, forceAutoload: shouldAutoload, theme: theme, didStart: $didStart)
                
            default:
                UnknownKindView(nrPost: nrPost, theme: theme)
            }
            
        }
    }
}

struct NoteTextRenderView_Previews: PreviewProvider {
    static var previews: some View {
        
        // With youtube link:
        // 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // Mention in end #[0]
        // 143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
                
                let event5 = PreviewFetcher.fetchNRPost("b2e209b3073f24b4d6c172965ad8dd8276ada68895d4ab8837cf3a57d3f1c947")
                //        let event5 = PreviewFetcher.fetchNRPost("143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3")
                
                let event4 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
                
                let event3 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
                
                let event2 = PreviewFetcher.fetchNRPost("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc")
                
                let event1 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
                
                let event0 = PreviewFetcher.fetchNRPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
                
                Group {
                    if (event0 != nil) {
                        NoteTextRenderView(nrPost:event0!, theme: Themes.default.theme)
                        Divider()
                    }
                    
                    if (event1 != nil) {
                        NoteTextRenderView(nrPost:event1!, theme: Themes.default.theme)
                        Divider()
                    }
                    
                    if (event2 != nil) {
                        NoteTextRenderView(nrPost:event2!, theme: Themes.default.theme)
                        Divider()
                    }
                }
                
                if (event3 != nil) {
                    NoteTextRenderView(nrPost:event3!, theme: Themes.default.theme)
                    Divider()
                }
                
                if (event4 != nil) {
                    NoteTextRenderView(nrPost:event4!, theme: Themes.default.theme)
                    Divider()
                }
                if (event5 != nil) {
                    NoteTextRenderView(nrPost:event5!, theme: Themes.default.theme)
                    Divider()
                }
            }
        }
    }
}
