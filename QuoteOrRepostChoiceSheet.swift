//
//  QuoteOrRepostChoiceSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/03/2023.
//

import SwiftUI

struct QuoteOrRepostChoiceSheet: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    @Environment(\.dismiss) var dismiss
    
    let event:Event
    @Binding var unpublishRepostId:UUID?
    @Binding var unpublishOriginalId:UUID?
    @Binding var showingNewQuoteRepost:Bool
    
    var body: some View {
        // repost
        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                if (ns.account != nil) {
                    print("🔄🔄🔄🔄🔄🔄🔄🔄")
                    event.reposted = true
                    event.mentionsCount += 1
                    ns.account?.addToReposts(event)
                    
                    // 1. create kind 7 event based on kind 1 event:    Event
                    let repostEvent = EventMessageBuilder.makeRepost(original: event)
                    
                    // 2. sign that event with account keys             Account
                    guard let signedEvent = try? ns.signEvent(repostEvent) else {
                        print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                        return
                    }
                    
                    unpublishRepostId = up.publish(signedEvent)
                    unpublishOriginalId = up.publish(event.toNEvent())
                    dismiss()
                }
            } label: { Label("Repost", systemImage: "arrow.2.squarepath").padding(.vertical, 5) }
            
            // quote tweet
            Button {
                showingNewQuoteRepost = true
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
    
    @State static var unpublishRepostId:UUID? = UUID()
    @State static var unpublishOriginalId:UUID? = UUID()
    @State static var showingNewQuoteRepost:Bool = true
    
    static var previews: some View {
        
        let event = PreviewFetcher.fetchEvent("c3a040feac185585f984147cdaf7a7ec5774b06db29ff25017c45026e470daeb")
        VStack {
            if let event {
                QuoteOrRepostChoiceSheet(event: event, unpublishRepostId: $unpublishRepostId, unpublishOriginalId: $unpublishOriginalId, showingNewQuoteRepost: $showingNewQuoteRepost)
                    .withPreviewEnvironment()
            }
        }
    }
}
