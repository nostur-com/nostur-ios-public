//
//  QuoteOrRepostChoiceSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/03/2023.
//

import SwiftUI

struct QuoteOrRepostChoiceSheet: View {
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    @Environment(\.dismiss) var dismiss
    
    let originalEvent:Event
    @Binding var quotePostEvent:Event?
    
    var body: some View {
        // repost
        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                if (ns.account != nil) {
                    print("🔄🔄🔄🔄🔄🔄🔄🔄")
//                    originalEvent.mentionsCount += 1

                    
                    // 1. create repost
                    let repost = EventMessageBuilder.makeRepost(original: originalEvent)
                    
                    // 2. sign that event with account keys             Account
                    guard let signedRepost = try? ns.signEvent(repost) else {
                        print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                        return
                    }
                    
                    up.publishNow(originalEvent.toNEvent()) // publish original
                    up.publishNow(signedRepost) // publish repost
                    sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: originalEvent.id))
                    dismiss()
                }
            } label: { Label("Repost", systemImage: "arrow.2.squarepath").padding(.vertical, 5) }
            
            // quote tweet
            Button {
                quotePostEvent = originalEvent
                dismiss()
            } label: { Label("Quote post", systemImage: "square.and.pencil").padding(.vertical, 5) }
                .padding(.vertical, 10)
            
            // cancel
            Button {
                dismiss()
            } label: { Text("Cancel").frame(width: 250) }
                .padding(.vertical, 10)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 10)
        
    }
}

struct QuoteOrRepostChoiceSheet_Previews: PreviewProvider {
    
    @State static var quotePostEvent:Event? = nil
    
    static var previews: some View {
        
        VStack {
            let event = PreviewFetcher.fetchEvent()
            
            if let event {
                QuoteOrRepostChoiceSheet(originalEvent: event, quotePostEvent: $quotePostEvent)
            }
        }
        .withPreviewEnvironment()
    }
}
