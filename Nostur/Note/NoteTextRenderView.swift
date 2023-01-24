//
//  NoteTextRenderView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI


// TODO: RESEARCH SWIFT USER GENERATED CONTEXT SANITIZING ETC.

// SHOULD DO:
// RENDER LINK PREVIEW (FIRST ONE IS ENOUGH)
// TAPPABLE @MENTIONS
// RENDER PICTURE THUMBNAIL, MAX 4?
// RENDER LN INVOICE?
// RENDER BITCOIN ADDR QR?



struct NoteTextRenderView: View {
    
    var event:Event?
    var allContacts:[Contact]?
    var renderedText:AttributedString? = nil
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil && allContacts != nil else {
            return nil
        }
        return allContacts?.first(where: { $0.pubkey == byPubkey })
    }
    
    init(event: Event? = nil, allContacts: [Contact]? = nil) {
        self.event = event
        self.allContacts = allContacts
        
        var text = (event?.content) ?? ""

        let pTags = event?.contactPubkeys()
        
        if (pTags == nil || pTags?.count == 0) {
            renderedText = AttributedString(text)
        }
        else {
            for index in pTags!.indices {
                let key = try! NIP19(prefix: "npub", hexString: pTags![index])
                if let contact = contact(byPubkey:pTags![index]) {
                    text = text.replacingOccurrences(of: "#[\(index)]", with: "[@\(contact.username)](nostr:\(key.displayString))")
                }
                else {
                    text = text.replacingOccurrences(of: "#[\(index)]", with: "[@\(String(pTags![index]).prefix(5))](nostr:\(key.displayString))")
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
        if (event != nil) && (allContacts != nil) {
            Text(renderedText!)
        }
        else if (allContacts == nil) {
            Text(event?.noteText ?? "")
        }
        else {
            Text("")
        }
    }
}

struct NoteTextRenderView_Previews: PreviewProvider {
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        let eventId = "1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0"
        
        let noteWithMentions = PreviewFetcher.fetchEvent(eventId)
        let allContacts = PreviewFetcher.allContacts()
        
        NoteTextRenderView(event:noteWithMentions, allContacts: allContacts)
            .withPreviewEnvironment()
    }
}
