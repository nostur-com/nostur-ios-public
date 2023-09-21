//
//  ZapButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import SwiftUI

// Zap button uses NWC if available, else just falls back to the old LightningButton
struct ZapButton: View {
    @EnvironmentObject private var theme: Theme
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    @ObservedObject private var ss:SettingsStore = .shared
    @State private var cancellationId:UUID? = nil
    @State private var customZapId:UUID? = nil
    @State private var activeColor = Theme.default.footerButtons
    
    private var tallyString:String {
        if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
            let fiatPrice = String(format: "$%.02f",(Double(footerAttributes.zapTally) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))
            return fiatPrice
        }
        return String(footerAttributes.zapTally.formatNumber)
    }
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
    }
    
    var body: some View {
        if ss.defaultLightningWallet.scheme.contains(":nwc:") && !ss.activeNWCconnectionId.isEmpty, let contact = nrPost.contact?.contact {
            if let cancellationId {
                HStack {
                    Image("BoltIconActive").foregroundColor(theme.footerButtons)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .onTapGesture {

                            self.cancellationId = nil
                            footerAttributes.cancelZap(cancellationId)                            
                            
                            activeColor = theme.footerButtons
                            L.og.info("⚡️ Zap cancelled")
                        }
                    AnimatedNumberString(number: tallyString).opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                }
            }
            // TODO elsif zap .failed .overlay error !
            else if footerAttributes.zapped {
                HStack {
                    Image("BoltIconActive").foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    AnimatedNumberString(number: tallyString).opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                }
            }
            else {
                HStack {
                    Image("BoltIcon")
                        .foregroundColor(activeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
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
                        )
                    AnimatedNumberString(number: tallyString).opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                }
            }
        }
        else {
            LightningButton(nrPost: nrPost)
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
        

        DataProvider.shared().bg.perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC:isNC, amount: Int64(selectedAmount), contact: contact, eventId: nrPost.id, event: nrPost.event, cancellationId: cancellationId!, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
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
