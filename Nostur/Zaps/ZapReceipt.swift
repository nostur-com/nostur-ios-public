//
//  ZapReceipt.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/10/2023.
//

import SwiftUI
import Combine

// Experiment with new "Processor" Combine mechanism

struct ZapReceipt: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    
    @ObservedObject public var nrPost: NRPost
    public let sats: Double
    public let receiptPubkey: String
    
    public var fromPubkey: String
    public let from: Event
    private var color: Color { randomColor(seed: fromPubkey) }

    @State private var name: String?
    @State private var pictureUrl: URL?
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var nrZapFrom: NRPost?
    
    @State var showMiniProfile = false
    
    public var isEmbedded: Bool = false
    
    var body: some View {
        if isEmbedded {
            embeddedView
        }
        else {
            normalView
        }
    }
        
    
    @ViewBuilder
    private var normalView: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        PostLayout(nrPost: nrPost, hideFooter: true, isDetail: false, theme: themes.theme) {
            
            content

        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, theme: themes.theme) {
            content
        }
    }
    
    @ViewBuilder
    var content: some View {
        HStack(alignment: .top) {
            VStack {
                InnerPFP(pubkey: fromPubkey, pictureUrl: pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER, color: color)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName:"bolt.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(themes.theme.accent)
                            .offset(x: 6, y: 6)
                    }
//                    .withoutAnimation() // seems to fix flying PFPs
                    .onTapGesture {
                        withAnimation { showMiniProfile = true }
                    }
                    .overlay(alignment: .topLeading) {
                        if (showMiniProfile) {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        sendNotification(.showMiniProfile,
                                                         MiniProfileSheetInfo(
                                                            pubkey: fromPubkey,
                                                            contact: nrZapFrom?.contact,
                                                            location: geo.frame(in: .global).origin
                                                         )
                                        )
                                        showMiniProfile = false
                                    }
                            }
                              .frame(width: 10)
                              .zIndex(100)
                              .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                              .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                                  showMiniProfile = false
                              }
                        }
                        navigateTo(ContactPath(key: fromPubkey), context: dim.id)
                    }
                
                Text(sats.satsFormatted)
                    .font(.title2)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(sats) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(sats != 0 ? 0.5 : 0)
                }
            }
         
            VStack(alignment: .leading, spacing: 3) { // Post container
                ZappedFrom(pubkey: fromPubkey, name: name, couldBeImposter: 0, createdAt: from.date, context: dim.id)
                
                if let nrZapFrom = nrZapFrom {
                    ContentRenderer(nrPost: nrZapFrom, isDetail:false, fullWidth: false, availableWidth: dim.availableNoteRowImageWidth(), theme: themes.theme)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment:.leading)
                }
                else {
                    Color.clear
                        .frame(height: 40)
                }
                
                ReceiptFrom(pubkey: receiptPubkey)
            }
            .task {
                bg().perform {
                    if let bgEvent = from.toBG() {
                        nrZapFrom = NRPost(event: bgEvent)
                    }
                }
                Kind0Processor.shared.receive
                    .subscribe(on: DispatchQueue.global())
                    .receive(on: DispatchQueue.global())
                    .filter { $0.pubkey == fromPubkey }
                    .sink { profile in
                        DispatchQueue.main.async {
                            name = profile.name
                            pictureUrl = profile.pictureUrl
                        }
                    }
                    .store(in: &subscriptions)
                
                Kind0Processor.shared.request.send(fromPubkey)
            }
        }
    }
}

struct ZappedFrom: View {
    let pubkey: String
    var name: String?
    var couldBeImposter: Int = 0
    var createdAt: Date
    var context: String = "Default"
    
    var body: some View {
        HStack {
            Text(name ?? String(pubkey.prefix(11)))
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .lineLimit(2)
                .layoutPriority(2)
                .onTapGesture {
                    navigateTo(ContactPath(key: pubkey, navigationTitle: name ?? String(pubkey.prefix(11))), context: context)
                }
            
            if couldBeImposter == 1 {
                PossibleImposterLabel(possibleImposterPubkey: pubkey)
            }
            
            Ago(createdAt)
                .equatable()
                .layoutPriority(2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct ReceiptFrom: View {
    @EnvironmentObject private var themes:Themes
    let pubkey:String
    
    @State private var name:String?
    @State private var pictureUrl:URL?
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        HStack {
            Text("Zap receipt from")
            InnerPFP(pubkey: pubkey, pictureUrl:pictureUrl, size: 20.0)
                .frame(width: 20.0, height: 20.0)
            Text(name ?? String(pubkey.prefix(11)))
        }
        .font(.footnote)
        .foregroundColor(themes.theme.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task {
            Kind0Processor.shared.receive
                .subscribe(on: DispatchQueue.global())
                .receive(on: DispatchQueue.global())
                .filter { $0.pubkey == pubkey }
                .sink { profile in
                    DispatchQueue.main.async {
                        name = profile.name
                        pictureUrl = profile.pictureUrl
                    }
                }
                .store(in: &subscriptions)
            
            Kind0Processor.shared.request.send(pubkey)
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
