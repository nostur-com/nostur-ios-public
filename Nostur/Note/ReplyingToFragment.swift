//
//  ReplyingToFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI

struct ReplyingToFragment: View {
    
    var cm:SocketPool = .shared
    
    @ObservedObject var event:Event // @Observed here can cause hang?? but needed...
    
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
            return event.replyTo!.pubkey!
        }
        if let firstEtagPubkey = event.contactPubkeys()?.first {
            return firstEtagPubkey
        }
        return "00000"
    }
    
    var body: some View {
        
        if (event.replyToId == nil) && (event.replyTo == nil) {
            EmptyView()
        }
        else {
            Text(try! AttributedString(markdown:"Replying to [@\(replyToUsername())](nostur:p:\(replyToPubkeyHex()))"))
                .foregroundColor(.secondary)
                .font(.system(size: 13))
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

struct ReplyingToFragment_Previews: PreviewProvider {
    static var previews: some View {
        
        
        // No replyTo.contact
        let event1 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        // With replyTo.contact
        let event2 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")

        // No reply at all.
        let event3 = PreviewFetcher.fetchEvent("d90c63ca06c0eab08d5c79d3991cd22b6c0e2f4e56167ae918343f2a9bc98ff1")
        
        VStack {
            ReplyingToFragment(event: event1!)
                .withPreviewEnvironment()
            Spacer()
            ReplyingToFragment(event: event2!)
                .withPreviewEnvironment()
            Spacer()
            ReplyingToFragment(event: event3!)
                .withPreviewEnvironment()
            Spacer()
        }
        
    }
}
