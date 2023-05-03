//
//  MinimalNoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct MinimalNoteTextRenderView: View {
    
    let vPost:VPost
    let lineLimit:Int
    
    
    init(vPost:VPost, lineLimit:Int = 10) {
        self.vPost = vPost
        self.lineLimit = lineLimit
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(vPost.plainText)//.border(.cyan)
                .lineLimit(lineLimit, reservesSpace: false)
                .textSelection(.enabled)
                .multilineTextAlignment(TextAlignment.leading)
                .foregroundColor(.primary.opacity(0.5))
                .lineSpacing(3)
                .padding(.vertical, 5)
        }
    }
}

struct MinimalNoteTextRenderView_Previews: PreviewProvider {
    static var previews: some View {
        
        // With youtube link:
        // 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // Mention in end #[0]
        // 143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3
            
        
        VStack {
            
            let event5 = PreviewFetcher.fetchVPost("b2e209b3073f24b4d6c172965ad8dd8276ada68895d4ab8837cf3a57d3f1c947")
            //        let event5 = PreviewFetcher.fetchVPost("143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3")
            
            let event4 = PreviewFetcher.fetchVPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
            
            let event3 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            
            let event2 = PreviewFetcher.fetchVPost("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc")
            
            let event1 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            
            let event0 = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
            
            Group {
                if let event0 {
                    MinimalNoteTextRenderView(vPost:event0)
                    Divider()
                }
                
                if let event1 {
                    MinimalNoteTextRenderView(vPost:event1)
                    Divider()
                }
                
                if let event2 {
                    MinimalNoteTextRenderView(vPost:event2)
                    Divider()
                }
            }
            
            if let event3 {
                MinimalNoteTextRenderView(vPost:event3)
                Divider()
            }
            
            if let event4 {
                MinimalNoteTextRenderView(vPost:event4)
                Divider()
            }
            if let event5 {
                MinimalNoteTextRenderView(vPost:event5)
                Divider()
            }
        }
        .withPreviewEnvironment()
    }
}
