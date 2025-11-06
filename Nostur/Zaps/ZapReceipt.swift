//
//  ZapReceipt.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/10/2023.
//

import SwiftUI

struct ZappedFrom: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    private let nrZapFrom: NRPost
    @ObservedObject private var nrContact: NRContact
    private var context: String = "Default"
    
    init(nrZapFrom: NRPost, context: String = "Default") {
        self.nrZapFrom = nrZapFrom
        self.nrContact = NRContact.instance(of: nrZapFrom.pubkey)
        self.context = context
    }
    
    
    
    var body: some View {
        HStack {
            Text(nrContact.anyName)
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .lineLimit(2)
                .layoutPriority(2)
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateToContact(pubkey: nrZapFrom.pubkey, nrContact: nrContact, nrPost: nrZapFrom, context: context)
                }
            
            PossibleImposterLabelView(nrContact: nrContact)
            
            Ago(nrZapFrom.createdAt)
                .equatable()
                .layoutPriority(2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct ReceiptFrom: View {
    @Environment(\.theme) private var theme
    let pubkey: String
    
    @ObservedObject private var nrContact: NRContact
    
    init(pubkey: String) {
        self.pubkey = pubkey
        self.nrContact = NRContact.instance(of: pubkey)
    }
    
    var body: some View {
        HStack {
            Text("Zap receipt from")
            InnerPFP(pubkey: pubkey, pictureUrl: nrContact.pictureUrl, size: 20.0)
                .frame(width: 20.0, height: 20.0)
            Text(nrContact.anyName)
        }
        .font(.footnote)
        .foregroundColor(theme.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task {
            QueuedFetcher.shared.enqueue(pTag: pubkey)
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadZaps()
    }) {
        
//        ProcessorTest(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")
        
        LazyVStack(spacing: GUTTER) {
            if let zapReceipt = PreviewFetcher.fetchEvent("eafca163fd997086016a41e56fa938932eaedae7b386b74954522bfb78fb41ca"),
               let zapFrom = zapReceipt.zapFromRequest {
                
                Box {
//                    ZapReceipt(sats: zapReceipt.naiveSats, receiptPubkey: zapReceipt.pubkey, fromPubkey: zapFrom.pubkey, from: zapFrom)
                }
            }    
            if let zapReceipt = PreviewFetcher.fetchEvent("3dc871c72de8bf563d675271a0ca3e5061287b228aa72983a651e0bf1fc14ad3"),
               let zapFrom = zapReceipt.zapFromRequest {
                
                Box {
//                    ZapReceipt(sats: zapReceipt.naiveSats, receiptPubkey: zapReceipt.pubkey, fromPubkey: zapFrom.pubkey, from: zapFrom)
                }
            }       
//            if let zapReceipt = PreviewFetcher.fetchNRPost("eafca163fd997086016a41e56fa938932eaedae7b386b74954522bfb78fb41ca") {
//                Box {
//                    ZapReceipt(nrPost: zapReceipt)
//                }
//            }            
//            if let zapReceipt = PreviewFetcher.fetchNRPost("c02948c6b0f5f4d602079d7bffdcf2794bd26857c5ff1a1f703918a19b7187fa") {
//                Box {
//                    ZapReceipt(nrPost: zapReceipt)
//                }
//            }
//            if let zapReceipt = PreviewFetcher.fetchNRPost("eafca163fd997086016a41e56fa938932eaedae7b386b74954522bfb78fb41ca") {
//                Box {
//                    ZapReceipt(nrPost: zapReceipt)
//                }
//            }
            
            
        }
    }
}
