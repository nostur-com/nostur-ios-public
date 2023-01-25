//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI
import LinkPresentation


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
    var allContacts:[Contact]?
    var renderedText:AttributedString? = nil
    var firstLinkInText:String? = nil
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil && allContacts != nil else {
            return nil
        }
        return allContacts?.first(where: { $0.pubkey == byPubkey })
    }
    
    @State var withLinkPreview = false
    
    init(event: Event? = nil, allContacts: [Contact]? = nil) {
        self.event = event
        self.allContacts = allContacts
        
        var text = (event?.content) ?? ""
        
        // TODO: maybe add helpers for widely used embeds so https:// is prefixed automagically if missing
        let urlMatches = text.matchingStrings(regex:#"(https:\/\/)[\w/\-?=%.]+\.[\w/\-?=%.]+"#)
        
        if urlMatches.count == 1 && urlMatches[0].count != 0 {
            firstLinkInText = urlMatches[0][0]
        }
        
        let tags = event?.tags()
        
        if (tags == nil || tags?.count == 0) {
            renderedText = AttributedString(text)
        }
        else {
            for index in tags!.indices {
                if (tags![index].type == "p") {
                    let key = try! NIP19(prefix: "npub", hexString: tags![index].pubkey)
                    if let contact = contact(byPubkey:tags![index].pubkey) {
                        text = text.replacingOccurrences(of: "#[\(index)]", with: "[@\(contact.username)](nostr:\(key.displayString))")
                    }
                    else {
                        text = text.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].pubkey).prefix(5))](nostr:\(key.displayString))")
                    }
                }
                if (tags![index].type == "e") {
                    let key = try! NIP19(prefix: "note", hexString: tags![index].id)
                    text = text.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(tags![index].id).prefix(10))](nostr:\(key.displayString))")
                }
            }
            do {
                renderedText = try AttributedString(markdown: text)
            }
            catch {
                renderedText = AttributedString(text)
                print(error)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (event != nil) && (allContacts != nil) {
                Text(renderedText!)
            }
            else if (allContacts == nil) {
                Text(event?.noteText ?? "")
            }
            else {
                Text("")
            }
            
            if (firstLinkInText != nil) {
                LinkPreview(url: URL(string: firstLinkInText!)!, togglePreview: $withLinkPreview)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onAppear {
//            let metadataProvider = LPMetadataProvider()
//            let url = URL(string: "https://www.apple.com/ipad")!
//            metadataProvider.startFetchingMetadata(for: url) { metadata, error in
//                if error != nil {
//                    // The fetch failed; handle the error.
//                    return
//                }
//                // TODO: Make use of fetched metadata.
//                linkPreview = LPLinkView(metadata: metadata!)
//                linkPreview.sizeToFit()
//            }
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
        
        let eventId = "576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113"
        
        let noteWithMentions = PreviewFetcher.fetchEvent(eventId)
        let allContacts = PreviewFetcher.allContacts()
        
        NoteTextRenderView(event:noteWithMentions, allContacts: allContacts)
            .withPreviewEnvironment()
    }
}
