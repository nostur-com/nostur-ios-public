//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI

// TODO: RESEARCH SWIFT USER GENERATED CONTEXT SANITIZING ETC.

struct NoteTextRenderView: View {
    var vPost:VPost
    var useLinelimit = true
    @State var viewSize:CGSize = .zero
    
    init(vPost: VPost, useLinelimit:Bool = true) {
        self.vPost = vPost
        self.useLinelimit = useLinelimit
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if canRender1063(vPost) {
                VStack {
                    if viewSize.width > 0 {
                        Kind1063(vPost, availableWidth: viewSize.width)
                    }
                    Color.clear.frame(height: 0)
                       .modifier(SizeModifier())
                       .onPreferenceChange(SizePreferenceKey.self) { size in
                           guard size.width > 0 else { return }
                           viewSize = size
                       }
                }
            }
            else if vPost.event.kind != 1 && (vPost.event.content ?? "").isEmpty {
                Label("kind \(Double(vPost.event.kind).clean) type not (yet) supported", systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .frame(maxWidth: .infinity)
                    .background(Color("LightGray").opacity(0.2))
            }
            else if (useLinelimit) {
                Text(vPost.renderedText)//.border(.cyan)
                    .lineLimit(10, reservesSpace: false)
                    .textSelection(.enabled)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(.primary)
                    .accentColor(Color("AccentColor"))
                    .tint(Color("AccentColor"))
                    .lineSpacing(3)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            else {
                Text(vPost.renderedText)//.border(.pink)
                    .textSelection(.enabled)
                    .multilineTextAlignment(TextAlignment.leading)
                    .foregroundColor(.primary)
                    .accentColor(Color("AccentColor"))
                    .tint(Color("AccentColor"))
                    .lineSpacing(3)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
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
        
        
        VStack {
            
            let event5 = PreviewFetcher.fetchVPost("b2e209b3073f24b4d6c172965ad8dd8276ada68895d4ab8837cf3a57d3f1c947")
            //        let event5 = PreviewFetcher.fetchVPost("143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3")
            
            let event4 = PreviewFetcher.fetchVPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
            
            let event3 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            
            let event2 = PreviewFetcher.fetchVPost("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc")
            
            let event1 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
            
            let event0 = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
            
            Group {
                if (event0 != nil) {
                    NoteTextRenderView(vPost:event0!)
                    Divider()
                }
                
                if (event1 != nil) {
                    NoteTextRenderView(vPost:event1!)
                        .withPreviewEnvironment()
                    Divider()
                }
                
                if (event2 != nil) {
                    NoteTextRenderView(vPost:event2!)
                        .withPreviewEnvironment()
                    Divider()
                }
            }
            
            if (event3 != nil) {
                NoteTextRenderView(vPost:event3!)
                    .withPreviewEnvironment()
                Divider()
            }
            
            if (event4 != nil) {
                NoteTextRenderView(vPost:event4!)
                    .withPreviewEnvironment()
                Divider()
            }
            if (event5 != nil) {
                NoteTextRenderView(vPost:event5!)
                    .withPreviewEnvironment()
                Divider()
            }
        }
        .withPreviewEnvironment()
    }
}
