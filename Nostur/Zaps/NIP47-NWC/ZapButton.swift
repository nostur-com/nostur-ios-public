//
//  ZapButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import SwiftUI

// Zap button uses NWC if available, else just falls back to the old LightningButton
struct ZapButton: View {
    @EnvironmentObject private var theme:Theme
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    @ObservedObject private var ss:SettingsStore = .shared
    @State private var cancellationId:UUID? = nil
    @State private var customZapId:UUID? = nil
    @State private var activeColor:Color? = nil
    @State private var isLoading = false
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    private var icon:String {
        return if isLoading { "hourglass.tophalf.filled" }
               else if (footerAttributes.zapped || cancellationId != nil) { "bolt.fill"}
               else { "bolt" }
    }
    
    
    var body: some View {
        Image(systemName: icon)
            .overlay(alignment: .leading) {
                AnimatedNumberString(number: footerAttributes.zapTally.formatNumber)
                    .opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                    .frame(width: 34)
                    .offset(x: 18)
                //                        AnimatedNumberString(number: "3.6M")
                //                            .frame(width: 34)
                //                            .offset(x: 18)
            }
            .padding(.trailing, 34)
            .foregroundColor(footerAttributes.zapped ? .yellow : theme.accent)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if ss.nwcReady {
                    if let cancellationId = cancellationId {
                        cancelZap(cancellationId)
                    }
                    else {
                        // do nothing
                    }
                }
                else {
                    nonNWCtap()
                }
            }
            .overlay {
                if ss.nwcReady, !footerAttributes.zapped, cancellationId == nil, let contact = nrPost.contact?.contact {
                    GeometryReader { geo in
                        Color.white.opacity(0.001)
                            .simultaneousGesture(
                                LongPressGesture()
                                    .onEnded { _ in
                                        guard isFullAccount() else { showReadOnlyMessage(); return }
                                        // Trigger custom zap
                                        customZapId = UUID()
                                        if let customZapId {
                                            sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: nrPost.anyName, customZapId: customZapId))
                                        }
                                    }
                            )
                            .highPriorityGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        self.triggerZap(strikeLocation: geo.frame(in: .global).origin, contact:contact)
                                    }
                            )
                            .onReceive(receiveNotification(.sendCustomZap)) { notification in
                                // Complete custom zap
                                let customZap = notification.object as! CustomZap
                                guard customZap.customZapId == customZapId else { return }
                                self.triggerZap(strikeLocation: geo.frame(in: .global).origin, contact:contact, zapMessage:customZap.publicNote, amount: customZap.amount)
                            }
                    }
                }
            }
    }
    
    func triggerZap(strikeLocation:CGPoint, contact:Contact, zapMessage:String = "", amount:Double? = nil) {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        sendNotification(.lightningStrike, LightningStrike(location:strikeLocation, amount: selectedAmount))
        withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
            activeColor = .yellow
        }
        cancellationId = UUID()
        footerAttributes.zapped = true
        
        
        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC:isNC, amount: Int64(selectedAmount), contact: contact, eventId: nrPost.id, event: nrPost.event, cancellationId: cancellationId!, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
        }
    }
    
    private func cancelZap(_ cancellationId:UUID) {
        self.cancellationId = nil
        footerAttributes.cancelZap(cancellationId)
        activeColor = theme.footerButtons
        L.og.info("⚡️ Zap cancelled")
    }
    
    private func nonNWCtap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard (nrPost.contact?.anyLud ?? false) else { return }
        isLoading = true
        
        if let lud16 = nrPost.contact!.lud16 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 100000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrPost.contact!.zapperPubkey = response.nostrPubkey!
                            }
                            // Old zap sheet
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrPost:nrPost, contact: nrPost.contact!.mainContact)
                            sendNotification(.showZapSheet, paymentInfo)
                            
                            //                            // Trigger custom zap
                            //                            customZapId = UUID()
                            //                            if let customZapId {
                            //                                sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(nrPost: nrPost!, customZapId: customZapId))
                            //                            }
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.og.error("🔴🔴 problem in lnurlp \(error)")
                }
            }
        }
        else if let lud06 = nrPost.contact!.lud06 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 200000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrPost.contact!.zapperPubkey = response.nostrPubkey!
                            }
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrPost:nrPost, contact: nrPost.contact!.mainContact)
                            sendNotification(.showZapSheet, paymentInfo)
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.og.error("🔴🔴🔴🔴 problem in lnurlp \(error)")
                }
            }
        }
    }
}

struct ZapButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadZaps()
        }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost("49635b590782cb1ab1580bd7e9d85ba586e6e99e48664bacf65e71821ae79df1") {
                    ZapButton(nrPost: nrPost)
                }
                
                Image("BoltIconActive").foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
    }
}
