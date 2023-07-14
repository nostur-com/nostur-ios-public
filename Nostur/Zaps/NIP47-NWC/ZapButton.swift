//
//  ZapButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import SwiftUI

// Zap button uses NWC if available, else just falls back to the old LightningButton
struct ZapButton: View {
    let er:ExchangeRateModel = .shared // Not Observed for performance
    var tally:Int64 // SATS (1000 SATS ~= 20 cent)
    @ObservedObject var nrPost:NRPost
    @ObservedObject var ss:SettingsStore = .shared
    @State var cancellationId:UUID? = nil
    @State var customZapId:UUID? = nil
    @State var activeColor = Self.grey
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    var tallyString:String {
        if (er.bitcoinPrice != 0.0) {
            let fiatPrice = String(format: "$%.02f",(Double(tally) / 100000000 * Double(er.bitcoinPrice)))
            return fiatPrice
        }
        return String(tally.formatNumber)
    }
    
    var body: some View {
        if ss.defaultLightningWallet.scheme.contains(":nwc:") && !ss.activeNWCconnectionId.isEmpty, let contact = nrPost.contact?.contact {
            if let cancellationId {
                HStack {
                    Image("BoltIconActive").foregroundColor(activeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .onTapGesture {
                            _ = Unpublisher.shared.cancel(cancellationId)
                            NWCRequestQueue.shared.removeRequest(byCancellationId: cancellationId)
                            NWCZapQueue.shared.removeZap(byCancellationId: cancellationId)
                            self.cancellationId = nil
                            nrPost.zapState = .cancelled
                            activeColor = Self.grey
                            L.og.info("⚡️ Zap cancelled")
                        }
                    AnimatedNumberString(number: tallyString).opacity(tally == 0 ? 0 : 1)
                }
            }
            // TODO elsif zap .failed .overlay error !
            else if [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(nrPost.zapState) {
                HStack {
                    Image("BoltIconActive").foregroundColor(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    AnimatedNumberString(number: tallyString).opacity(tally == 0 ? 0 : 1)
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
                                                   guard NosturState.shared.account != nil else { return }
                                                   guard NosturState.shared.account?.privateKey != nil else {
                                                       NosturState.shared.readOnlyAccountSheetShown = true
                                                       return
                                                   }
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
                    AnimatedNumberString(number: tallyString).opacity(tally == 0 ? 0 : 1)
                }
            }
        }
        else {
            LightningButton(tally:tally, nrPost: nrPost)
        }
    }
    
    func triggerZap(strikeLocation:CGPoint, contact:Contact, zapMessage:String = "", amount:Double? = nil) {
        guard let account = NosturState.shared.account else { return }
        guard NosturState.shared.account?.privateKey != nil else {
            NosturState.shared.readOnlyAccountSheetShown = true
            return
        }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        sendNotification(.lightningStrike, LightningStrike(location:strikeLocation, amount: selectedAmount))
        withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
            activeColor = .yellow
        }
        cancellationId = UUID()
        nrPost.zapState = .initiated
        

        DataProvider.shared().bg.perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC:isNC, amount: Int64(selectedAmount), contact: contact, eventId: nrPost.id, event: nrPost.event, cancellationId: cancellationId!, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
            nrPost.event.zapState = .initiated
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
                    ZapButton(tally:nrPost.zapTally, nrPost: nrPost)
                }
                
                
                Image("BoltIconActive").foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
    }
}
