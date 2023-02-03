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
        
    var event:Event?
    var taggedContacts:[Contact]
    var renderedText:AttributedString? = nil
    var firstLinkInText:String? = nil
//    @State var previewIsReady = false
    
    @State private var metadata: LPLinkMetadata?
    
//    @State var isVisible = false
    
//    var disableLinkPreviews = false
//    @State var linkMetadata:LPLinkMetadata? = nil
    
//    @State var linkPreview:LPLinkView? = nil
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return taggedContacts.first(where: { $0.pubkey == byPubkey })
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
    
    private func renderMentions(_ text:String) -> AttributedString? {
        let tags = event?.tags()
        var newText = text
        
        if (tags == nil || tags?.count == 0) {
            return AttributedString(text)
        }
        else {
            for index in tags!.indices {
                if (tags![index].type == "p") {
                    
                    if (1 == 1) {
                        // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                        let key = try! NIP19(prefix: "npub", hexString: tags![index].pubkey)
                        if let contact = contact(byPubkey:tags![index].pubkey) {
                            newText = newText.replacingOccurrences(of: "#[\(index)]", with: "[@\(contact.username)](nostr:\(key.displayString))")
                        }
                        else {
                            newText = newText.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].pubkey).prefix(5))](nostr:\(key.displayString))")
                        }
                    }
                    else {
                        newText = newText.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].pubkey).prefix(5))](nostur:p:\(tags![index].pubkey))")
                    }
                }
                if (tags![index].type == "e") {
                    
                    if (1 == 1) {
                        // TODO: NIP19 bech32 is very slow, with hundreds of rows it slows down UI noticeably, so disable for now
                        let key = try! NIP19(prefix: "note", hexString: tags![index].id)
                        newText = newText.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].id).prefix(10))](nostr:\(key.displayString))")
                    }
                    else {
                        newText = newText.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].id).prefix(10))](nostur:e:\(tags![index].id))")
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

    init(event: Event? = nil, taggedContacts: [Contact] = []) {
        self.event = event
        self.taggedContacts = taggedContacts
        let text = (event?.content) ?? ""
        self.firstLinkInText = getFirstLinkInText(text)
        self.renderedText = renderMentions(text)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (event != nil) && (taggedContacts.count > 0) {
                Text(renderedText!)
                    .lineLimit(4, reservesSpace: true)
                    .textSelection(.enabled)
                    .multilineTextAlignment(TextAlignment.leading)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
            }
            else if (taggedContacts.count == 0) {
                Text(event?.noteText ?? "")
                    .lineLimit(4, reservesSpace: true)
                    .textSelection(.enabled)
                    .multilineTextAlignment(TextAlignment.leading)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .padding(.vertical, 5)
            }
            else { Text("") }
            
            if (1 == 2 && firstLinkInText != nil) {
//                LinkPreview(url: URL(string:firstLinkInText!)!, previewIsReady: $previewIsReady)
                VStack {
                            if metadata != nil {
                                LinkView(metadata: metadata!)
                            } else {
                                ProgressView()
                            }
                        }
                        .onAppear(perform: fetchMetadata)
            }
            
//            if (linkPreview != nil) {
//                linkPreview!
//                    .frame(height: 300)
//            }
//            if (firstLinkInText != nil) {
//                if (!disableLinkPreviews) {
//                    if (linkMetadata != nil) {
//                        LinkPreview(url: URL(string: firstLinkInText!)!, metadata: linkMetadata)
//                    }
//                    else {
//                        LinkPreview(url: URL(string: firstLinkInText!)!)
//                    }
//                    //                    .aspectRatio(contentMode: .fit)
////                        .frame(height: 300)
//                }
//            }
        }
        
        
//        .onAppear {
//            if (firstLinkInText != nil) && (previewIsReady) {
//                isVisible = true
//            }
//        }
//        .onChange(of: previewIsReady) { newValue in
//            if (newValue == true && isVisible != true) {
//                isVisible = true
//            }
//        }
//        .task {
//            if (firstLinkInText != nil) {
//                let url = URL(string: firstLinkInText!)!
//                let metadata = LinkPreviewCache.shared.retrieveObject(at: url)
//                if (metadata != nil) {
//                    self.linkMetadata = metadata
//                }
//                else {
//                    let provider = LPMetadataProvider()
////                    do {
//
//                        if let metadata = try? await provider.startFetchingMetadata(for: url) {
//                            LinkPreviewCache.shared.setObject(for: url, value: metadata)
//                            DispatchQueue.main.async {
//                                linkMetadata = metadata
//                            }
//                        }
////                    }
////                    catch {
////                        print("🫂🫂🫂")
////                        print(error)
////                    }
//                }
//            }
//        }
    }
    
    private func fetchMetadata() {
        let provider = LPMetadataProvider()
        let url = URL(string: firstLinkInText!)!
        provider.startFetchingMetadata(for: url) { metadata, error in
            oyooy(metadata: metadata)
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
        
        let eventId = "143efe07393c5b07efbe6ea1fc66c39cb985b98f8844650edd00fbcb041228a3"
        
        let noteWithMentions = PreviewFetcher.fetchEvent(eventId)
        let allContacts = PreviewFetcher.allContacts()
        
        NoteTextRenderView(event:noteWithMentions, taggedContacts: allContacts)
            .withPreviewEnvironment()
    }
}
