//
//  ReplyingToFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI

struct ReplyingToFragment: View {
    
    @Environment(\.managedObjectContext) var viewContext
    private let sp:SocketPool = .shared
    
    @ObservedObject var event:Event
    
    // gets event.replyTo.contact or event.firstPtag
    func replyToUsername() -> String {
        if (event.replyTo != nil) {
            let username = event.replyTo!.contact?.username ?? String(event.replyTo!.authorKey.prefix(5))
            return username == "" ? event.replyTo!.contact?.display_name ?? String(event.replyTo!.authorKey.prefix(5)) : username
        }
        if let firstEtagPubkey = event.contactPubkeys()?.first {
            return String(firstEtagPubkey.prefix(5))
        }
        return "00000"
    }
    
    func replyToPubkeyHex() -> String {
        if (event.replyTo != nil) {
            return event.replyTo!.pubkey
        }
        if let firstEtagPubkey = event.contactPubkeys()?.first {
            return firstEtagPubkey
        }
        return "00000"
    }
    
    func contactUsername(fromPubkey pubkey:String) -> String {
        if let eventContact = event.contact, eventContact.pubkey == pubkey {
            return eventContact.username
        }
        if let contact = event.contacts?.first(where: { $0.pubkey == pubkey }) {
            return contact.username
        }
        // SLOW?
        if let contact = Contact.fetchByPubkey(pubkey, context: viewContext) {
            return contact.username
        }
        do {
            return String((try NIP19(prefix: "npub", hexString: pubkey).displayString).prefix(11))
        }
        catch {
            return  "⏤⏤"
        }
    }
    
    var body: some View {
        if (event.replyToId == nil) && (event.replyTo == nil) {
            EmptyView()
        }
        else {
            let pTags = Set(event.tags().filter { $0.type == "p" }.map { $0.pubkey })
            let pTagsAsStrings = pTags.map { pubkey in
                return "[@\(contactUsername(fromPubkey: pubkey))](nostur:p:\(pubkey))"
            }
            if (pTagsAsStrings.count > 6) {
                Text(try! AttributedString(markdown:"Replying to: " + pTagsAsStrings.prefix(4).joined(separator: ", ") + " and \(pTagsAsStrings.count-4) others"))
                    .foregroundColor(.secondary)
                //                .font(.system(size: 13))
                    .fontWeight(.light)
            }
            else if (pTagsAsStrings.count > 0) {
                Text(try! AttributedString(markdown:"Replying to: " + pTagsAsStrings.joined(separator: ", ")))
                    .foregroundColor(.secondary)
                //                .font(.system(size: 13))
                    .fontWeight(.light)
                //                .onAppear {
                //                    //TODO: DOESNT HANG ANY MORE?? OR??
                //                    // TODO: THIS CODE CAUSES TOO MANY SUBSCRIPTIONS....
                //                    /// THIS CODE CAUSES HANG WHEN FAST SCROLLING!
                //                    /// THIS CODE CAUSES HANG WHEN FAST SCROLLING!
                //                    /// THIS CODE CAUSES HANG WHEN FAST SCROLLING!
                //                    if (event.replyTo == nil) && (event.replyToId != nil) {
                //                        // is this the best place for this .REQ?
                //                        // Somewhere .onAppear? Not in parse of receive because can lead to infinite fetching?
                //
                //                        print("🟢 ReplyingToFragment.onAppear .replyTo + replyToId == nil so: REQ.0+1:\(replyToPubkeyHex())+\(event.replyToId!)")
                //
                //                        //TODO: COMBINE IN 1 REQ:
                //                        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: replyToPubkeyHex())))
                //
                //                        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
                //                    }
                //                    /// THIS CODE CAUSES HANG WHEN FAST SCROLLING!
                //                    /// THIS CODE CAUSES HANG WHEN FAST SCROLLING!
                //                }
            }
        }
    }
}

struct ReplyingToFragment_Previews: PreviewProvider {
    static var previews: some View {
        
        
        // No replyTo.contact
        let event1 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        // With replyTo.contact
        let event2 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        // No reply at all.
        let event3 = PreviewFetcher.fetchEvent("d90c63ca06c0eab08d5c79d3991cd22b6c0e2f4e56167ae918343f2a9bc98ff1")
        
        VStack {
            if (event1 != nil) {
                ReplyingToFragment(event: event1!)
                Spacer()
            }
        
            if (event2 != nil) {
                ReplyingToFragment(event: event2!)
                Spacer()
            }
            
            if (event3 != nil) {
                ReplyingToFragment(event: event3!)
                Spacer()
            }
        }
        .withPreviewEnvironment()
        
    }
}
