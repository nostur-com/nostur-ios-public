//
//  SmoothTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2023.
//

import SwiftUI

//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

// TODO: WHY DONT WE RENDER THE TEXT AT IMPORT??? SO IT DOESNT SLOW WHEN SCROLLING!!!
// TODO: WHY DONT WE RENDER THE TEXT AT IMPORT??? SO IT DOESNT SLOW WHEN SCROLLING!!!
// TODO: WHY DONT WE RENDER THE TEXT AT IMPORT??? SO IT DOESNT SLOW WHEN SCROLLING!!!
// TODO: WHY DONT WE RENDER THE TEXT AT IMPORT??? SO IT DOESNT SLOW WHEN SCROLLING!!!
struct SmoothNoteTextRenderView: View {
    
    var event:Event
    var renderedText:AttributedString? = nil
    var tags:[NEventTag]
    var useLinelimit = true
        
    func contactUsername(fromPubkey pubkey:String) -> String {
        if let contact = event.contacts?.first(where: { $0.pubkey! == pubkey }) {
            return contact.username
        }
        do {
            return String((try NIP19(prefix: "npub", hexString: pubkey).displayString).prefix(11))
        }
        catch {
            return  "⏤⏤"
        }
    }
    
    private func renderMentions(_ text:String) -> AttributedString? { // This is slow??
        var newText = text
        
        if (tags.count == 0) {
            return AttributedString(text)
        }
        else {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(contactUsername(fromPubkey: tags[index].pubkey))](nostur:p:\(tags[index].pubkey))")
                }
                if (tags[index].type == "e") {
                    // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(key.displayString).prefix(12))](nostur:e:\(tags[index].id))")
                }
            }
            do {
                let finalText = try AttributedString(markdown: newText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                return finalText
            }
            catch {
                let finalText = AttributedString(text)
                print(error)
                return finalText
            }
        }
    }
    
    init(event: Event, useLinelimit:Bool = true) {
        self.event = event
        self.tags = event.tags()
        let text = event.content ?? ""
        self.renderedText = renderMentions(text)
        self.useLinelimit = useLinelimit
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (tags.count > 0) {
                if (useLinelimit) {
                    Text(renderedText!)//.border(.cyan)
                        .lineLimit(10, reservesSpace: false)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                }
                else {
                    Text(renderedText!)//.border(.pink)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                }
            }
            else if (tags.count == 0) {
                if (useLinelimit) {
                    Text(event.noteText)//.border(.green)
                        .lineLimit(10, reservesSpace: false)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                }
                else {
                    Text(event.noteText)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                }
            }
            else { Text("") }            
        }
    }
}

struct SmoothNoteTextRenderView_Previews: PreviewProvider {
    static var previews: some View {
        
        // With youtube link:
        // 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // Mention in end #[0]
        // 143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3
        
        let event5 = PreviewFetcher.fetchEvent("b2e209b3073f24b4d6c172965ad8dd8276ada68895d4ab8837cf3a57d3f1c947")
        //        let event5 = PreviewFetcher.fetchEvent("143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3")
        
        let event4 = PreviewFetcher.fetchEvent("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        
        let event3 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event2 = PreviewFetcher.fetchEvent("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc")
        
        let event1 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event0 = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        
        VStack {
            Group {
                if (event0 != nil) {
                    SmoothNoteTextRenderView(event:event0!)
                        .withPreviewEnvironment()
                    Divider()
                }
                
                if (event1 != nil) {
                    SmoothNoteTextRenderView(event:event1!)
                        .withPreviewEnvironment()
                    Divider()
                }
                
                if (event2 != nil) {
                    SmoothNoteTextRenderView(event:event2!)
                        .withPreviewEnvironment()
                    Divider()
                }
            }
            
            if (event3 != nil) {
                SmoothNoteTextRenderView(event:event3!)
                    .withPreviewEnvironment()
                Divider()
            }
            
            if (event4 != nil) {
                SmoothNoteTextRenderView(event:event4!)
                    .withPreviewEnvironment()
                Divider()
            }
            if (event5 != nil) {
                SmoothNoteTextRenderView(event:event5!)
                    .withPreviewEnvironment()
                Divider()
            }
        }
    }
}
