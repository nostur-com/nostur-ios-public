//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI

// TODO: RESEARCH SWIFT USER GENERATED CONTEXT SANITIZING ETC.

struct NoteTextRenderView: View {
    var event:Event
    
    var renderedText:AttributedString? = nil
    var useLinelimit = true

    
    init(event: Event, useLinelimit:Bool = true) {
        self.event = event
        self.renderedText = event.renderedText()
        self.useLinelimit = useLinelimit
    }
    
    var body: some View {
        HStack(alignment: .top) {
                if (useLinelimit) {
                    Text(renderedText!)//.border(.cyan)
                        .lineLimit(10, reservesSpace: false)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                else {
                    Text(renderedText!)//.border(.pink)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            Spacer()
        }
    }
}

extension Event {
    
    func contactUsername(fromPubkey pubkey:String) -> String {
        if let contact = contacts?.first(where: { $0.pubkey == pubkey }) {
            return contact.username
        }
        // TODO: THIS IS SLOW?
        if let contact = Contact.fetchByPubkey(pubkey, context: EventsProvider.shared.container.viewContext) {
            return contact.username
        }
        do {
            return String((try NIP19(prefix: "npub", hexString: pubkey).displayString).prefix(11))
        }
        catch {
            return  "⏤⏤"
        }
    }
    
    // Takes a string and replaces any link with a markdown link. Also handles subdomains
    static func replaceURLsWithMarkdownLinks(in string: String) -> String {
        return string
            .replacingOccurrences(of: #"(?<!https?:\/\/)(?<!\S)[a-zA-Z0-9\.]+(?:\.[a-zA-Z]+)+([\/\?\=\&\#\.]\@?[\w-]+)*\/?"#,
                                  with: "[$0](https://$0)",
                                  options: .regularExpression) // REPLACE ALL DOMAINS WITHOUT PROTOCOL, WITH MARKDOWN LINK AND ADD PROTOCOL
            .replacingOccurrences(of: #"(?<!\S)([\w+]+\:\/\/)?[a-zA-Z0-9\.]+(?:\.[a-zA-Z]+)+([\/\?\=\&\#\.]\@?[\w-]+)*\/?"#,
                                  with: "[$0]($0)",
                                  options: .regularExpression) // REPLACE THE REMAINING URLS THAT HAVE PROTOCOL, BUT IGNORE ALREADY MARKDOWNED LINKS
    }
    
    func renderedText() -> AttributedString? {
        var newText = noteText
        let tags = tags()
        if (tags.count > 0) {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    
                    if (1 == 1) {
                        newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(contactUsername(fromPubkey: tags[index].pubkey))](nostur:p:\(tags[index].pubkey))")
                    }
                    else {
                        newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(tags[index].pubkey).prefix(5))](nostur:p:\(tags[index].pubkey))")
                    }
                }
                if (tags[index].type == "e") {
                    if (1 == 1) {
                        // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                        let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                        newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(key.displayString).prefix(12))](nostur:e:\(tags[index].id))")
                    }
                    else {
                        newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(tags[index].id).prefix(10))](nostur:e:\(tags[index].id))")
                    }
                }
            }
        }
        do {
            var newText = Event.replaceURLsWithMarkdownLinks(in: newText)
            let finalText = try AttributedString(markdown: newText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return finalText
        }
        catch {
            let finalText = AttributedString(newText)
            print(error)
            return finalText
        }
    }
    
    func copyPasteText() -> String {
        var newText = noteText
        let tags = tags()
        if (tags.count > 0) {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(contactUsername(fromPubkey: tags[index].pubkey))")
                }
                if (tags[index].type == "e") {
                    // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                    let key = try! NIP19(prefix: "note1", hexString: tags[index].id)
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "@\(String(key.displayString).prefix(12))")
                }
            }
        }
        return newText
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
                    NoteTextRenderView(event:event0!)
                        .withPreviewEnvironment()
                    Divider()
                }
                
                if (event1 != nil) {
                    NoteTextRenderView(event:event1!)
                        .withPreviewEnvironment()
                    Divider()
                }
                
                if (event2 != nil) {
                    NoteTextRenderView(event:event2!)
                        .withPreviewEnvironment()
                    Divider()
                }
            }
            
            if (event3 != nil) {
                NoteTextRenderView(event:event3!)
                    .withPreviewEnvironment()
                Divider()
            }
            
            if (event4 != nil) {
                NoteTextRenderView(event:event4!)
                    .withPreviewEnvironment()
                Divider()
            }
            if (event5 != nil) {
                NoteTextRenderView(event:event5!)
                    .withPreviewEnvironment()
                Divider()
            }
        }
    }
}
