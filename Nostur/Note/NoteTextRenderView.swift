//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI


import UIKit
import LinkPresentation


@MainActor
struct LinkView: UIViewRepresentable {
    typealias UIViewType = LPLinkView
    
    var metadata: LPLinkMetadata?
    
    @MainActor
    func makeUIView(context: Context) -> LPLinkView {
        guard let metadata = metadata else { return LPLinkView() }
        let linkView = LPLinkView(metadata: metadata)
        return linkView
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {

    }
}


// TODO: RESEARCH SWIFT USER GENERATED CONTEXT SANITIZING ETC.

// SHOULD DO:
// RENDER LINK PREVIEW (FIRST ONE IS ENOUGH)
// TAPPABLE @MENTIONS
// RENDER PICTURE THUMBNAIL, MAX 4?
// RENDER LN INVOICE?
// RENDER BITCOIN ADDR QR?


struct LinkPreviewCache {
    static var shared:LRUCache<URL, LPLinkMetadata> = {
        let cache = LRUCache<URL, LPLinkMetadata>(capacity: 100)
        return cache
    }()
}

struct NoteTextRenderView: View {
        
    var event:Event
    var taggedContacts:[Contact]
    
    var renderedText:AttributedString? = nil
    var firstLinkInText:String? = nil
    var tags:[NEventTag]
    var useLinelimit = true

    @State private var metadata: LPLinkMetadata?

    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return taggedContacts.first(where: { $0.pubkey! == byPubkey! })
    }
    
    private func getFirstLinkInText(_ text:String) -> String? {
        // TODO: maybe add helpers for widely used embeds so https:// is prefixed automagically if missing
        let urlMatches = text.matchingStrings(regex:#"(https:\/\/)[\w/\-?=%.]+\.[\w/\-?=%.]+"#)
        
        if urlMatches.count == 1 && urlMatches[0].count != 0 {
            let firstLinkInText = urlMatches[0][0]
            return firstLinkInText
        }
        return nil
    }
    
    private func renderMentions(_ text:String) -> AttributedString? { // This is slow??
        var newText = text
        
        if (tags.count == 0) {
            return AttributedString(text)
        }
        else {
            for index in tags.indices {
                if (tags[index].type == "p") {
                    
                    if (1 == 1) {
                        // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                        let key = try! NIP19(prefix: "npub1", hexString: tags[index].pubkey)
                        if let contact = contact(byPubkey:tags[index].pubkey) {
                            newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(contact.username)](nostur:p:\(tags[index].pubkey))")
                        }
                        else {
                            newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "[@\(String(key.displayString).prefix(12))](nostur:p:\(tags[index].pubkey))")
                        }
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
            do {
                let finalText = try AttributedString(markdown: newText)
                return finalText
            }
            catch {
                let finalText = AttributedString(text)
                print(error)
                return finalText
            }
        }
    }

    init(event: Event, taggedContacts: [Contact] = [], useLinelimit:Bool = true) {
        self.event = event
        self.tags = event.tags() ?? []
        self.taggedContacts = taggedContacts
        let text = event.content ?? ""
        self.firstLinkInText = getFirstLinkInText(text)
        self.renderedText = renderMentions(text)
        self.useLinelimit = useLinelimit
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (tags.count > 0) {
                if (useLinelimit) {
                    Text(renderedText!)
                        .lineLimit(10, reservesSpace: false)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
//                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.vertical, 5)
                }
                else {
                    Text(renderedText!)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
//                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.vertical, 5)
                }
            }
            else if (tags.count == 0) {
                if (useLinelimit) {
                    Text(event.noteText)
                        .lineLimit(4, reservesSpace: false)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
//                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.vertical, 5)
                }
                else {
                    Text(event.noteText)
                        .textSelection(.enabled)
                        .multilineTextAlignment(TextAlignment.leading)
//                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.vertical, 5)
                }
            }
            else { Text("") }
            
            if (1 == 1 && firstLinkInText != nil && !useLinelimit) {
                VStack {
                            if metadata != nil {
                                LinkView(metadata: metadata!)
                            } else {
                                HStack {
                                    Spacer()
                                    ProgressView().padding(20)
                                    Spacer()
                                }
                            }
                        }
                        .onAppear(perform: fetchMetadata)
            }
        }
    }
    
    private func fetchMetadata() {
        let provider = LPMetadataProvider()
        let url = URL(string: firstLinkInText!)!
        Task {
            let metadata = try await provider.startFetchingMetadata(for: url)
            await oyooy(metadata: metadata)
        }
    }
    
    @MainActor
    func oyooy(metadata:LPLinkMetadata?) {
        if let md = metadata {
            self.metadata = md
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
        
        let event5 = PreviewFetcher.fetchEvent("143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3")
        
        let event4 = PreviewFetcher.fetchEvent("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        
        let event3 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event2 = PreviewFetcher.fetchEvent("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc")
        
        let event1 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event0 = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        
        let allContacts = PreviewFetcher.allContacts()
        
        VStack {
            Group {
                NoteTextRenderView(event:event0!, taggedContacts: allContacts)
                    .withPreviewEnvironment()
                Divider()
                
                NoteTextRenderView(event:event1!, taggedContacts: allContacts)
                    .withPreviewEnvironment()
                Divider()
                
                NoteTextRenderView(event:event2!, taggedContacts: allContacts)
                    .withPreviewEnvironment()
                Divider()
            }
            
//            Text(allContacts.count.description)
            NoteTextRenderView(event:event3!, taggedContacts: allContacts)
                .withPreviewEnvironment()
            Divider()
            
            NoteTextRenderView(event:event4!, taggedContacts: allContacts)
                .withPreviewEnvironment()
            Divider()
            
            NoteTextRenderView(event:event5!, taggedContacts: allContacts)
                .withPreviewEnvironment()
            Divider()
        }
    }
}
