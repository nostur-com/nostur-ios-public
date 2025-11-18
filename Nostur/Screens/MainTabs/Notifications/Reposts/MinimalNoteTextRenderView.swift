//
//  MinimalNoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct MinimalNoteTextRenderView: View {
    
    @ObservedObject var nrPost:NRPost
    var lineLimit:Int = 10
    var textColor: Color = .primary.opacity(0.5)
    
    var body: some View {
        VStack(alignment: .leading) {
            if #available(iOS 16.0, *) {
                Text(nrPost.plainText)//.border(.cyan)
                    .lineLimit(lineLimit, reservesSpace: false)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(textColor)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
            else {
                Text(nrPost.plainText)//.border(.cyan)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(textColor)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
        }
    }
}

struct MinimalNoteTextRenderViewText: View {
    
    public var plainText:String
    public var lineLimit:Int = 10
    
    var body: some View {
        VStack(alignment: .leading) {
            if #available(iOS 16.0, *) {
                Text(plainText)
                    .lineLimit(lineLimit, reservesSpace: false)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(.primary.opacity(0.5))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
            else {
                Text(plainText)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(.primary.opacity(0.5))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
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
                    if let event0 {
                        MinimalNoteTextRenderView(nrPost:event0)
                        Divider()
                    }
                    
                    if let event1 {
                        MinimalNoteTextRenderView(nrPost:event1)
                        Divider()
                    }
                    
                    if let event2 {
                        MinimalNoteTextRenderView(nrPost:event2)
                        Divider()
                    }
                }
                
                if let event3 {
                    MinimalNoteTextRenderView(nrPost:event3)
                    Divider()
                }
                
                if let event4 {
                    MinimalNoteTextRenderView(nrPost:event4)
                    Divider()
                }
                if let event5 {
                    MinimalNoteTextRenderView(nrPost:event5)
                    Divider()
                }
            }
        }
    }
}
