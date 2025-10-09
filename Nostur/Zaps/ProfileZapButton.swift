//
//  ProfileZapButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/07/2023.
//

import SwiftUI

// Zap button uses NWC if available, else just falls back to the old LightningButton
struct ProfileZapButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.availableWidth) private var availableWidth
    private let er: ExchangeRateModel = .shared // Not Observed for performance
    
    @ObservedObject var nrContact: NRContact
    public var zapEtag: String?
    
    @ObservedObject private var ss: SettingsStore = .shared
    @State private var isZapped = false
    @State private var cancellationId: UUID? = nil
    @State private var customZapId: String? = nil
    @State private var activeColor = Self.grey
    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
    
    var body: some View {
        if ss.nwcReady {
            if let cancellationId {
                HStack {
                    Text("Zapped \(Image(systemName: "bolt.fill"))", comment: "Text in zap button after zapping")
                        .padding(.horizontal, 10)
                        .lineLimit(1)
                        .frame(width: 160, height: 30)
                        .font(.caption.weight(.heavy))
                        .foregroundColor(Color.yellow)
                        .background(Color.secondary)
                        .cornerRadius(20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(.gray, lineWidth: 1)
                        }
                        .onTapGesture {
                            _ = Unpublisher.shared.cancel(cancellationId)
                            NWCRequestQueue.shared.removeRequest(byCancellationId: cancellationId)
                            NWCZapQueue.shared.removeZap(byCancellationId: cancellationId)
                            self.cancellationId = nil
                            // TODO: MOVE state to contact (maybe increase lightning ring size)
                            activeColor = Self.grey
                            isZapped = false
                            nrContact.zapState = .cancelled
                            ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrContact.pubkey, eTag: zapEtag, zapState: .cancelled))
                            L.og.info("⚡️ Zap cancelled")
                        }
                }
            }
            // TODO elsif zap .failed .overlay error !
            else if isZapped {
                HStack {
                    Text("Zapped \(Image(systemName: "bolt.fill"))", comment: "Text in zap button after zapping")
                        .padding(.horizontal, 10)
                        .lineLimit(1)
                        .frame(width: 160, height: 30)
                        .font(.caption.weight(.heavy))
                        .foregroundColor(Color.yellow)
                        .background(Color.secondary)
                        .cornerRadius(20)
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(.gray, lineWidth: 1)
                        }
                }
            }
            else {
                Text("Send \(ss.defaultZapAmount.clean) sats \(Image(systemName: "bolt.fill"))")
                    .padding(.horizontal, 10)
                    .lineLimit(1)
                    .frame(width: 160, height: 30)
                    .font(.caption.weight(.heavy))
                    .foregroundColor(Color.white)
                    .background(Color.secondary)
                    .cornerRadius(20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.gray, lineWidth: 1)
                    }
                    .overlay(
                        GeometryReader { geo in
                            Color.white.opacity(0.001)
                                .simultaneousGesture(
                                       LongPressGesture()
                                           .onEnded { _ in
                                               guard isFullAccount() else { showReadOnlyMessage(); return }
                                               // Trigger custom zap
                                               customZapId = String()
                                               if let customZapId {
                                                   sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: nrContact.anyName, customZapId: customZapId))
                                               }
                                           }
                                   )
                                   .highPriorityGesture(
                                       TapGesture()
                                           .onEnded { _ in
                                               let point = CGPoint(x: geo.frame(in: .global).origin.x + 55, y: geo.frame(in: .global).origin.y + 10)
                                               self.triggerZap(strikeLocation: point, nrContact: nrContact)
                                           }
                                   )
                                   .onReceive(receiveNotification(.sendCustomZap)) { notification in
                                       // Complete custom zap
                                       let customZap = notification.object as! CustomZap
                                       guard customZapId != nil && customZap.customZapId == customZapId else { return }
                                       
                                       let point = CGPoint(x: geo.frame(in: .global).origin.x + 55, y: geo.frame(in: .global).origin.y + 10)
                                       self.triggerZap(strikeLocation: point, nrContact: nrContact, zapMessage: customZap.publicNote, amount: customZap.amount)
                                   }
                        }
                    )
                    .onAppear {
                        isZapped = [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(nrContact.zapState)
                    }
            }
        }
        else {
            ProfileLightningButton(nrContact: nrContact, zapEtag: zapEtag)
        }
    }
    
    func triggerZap(strikeLocation: CGPoint, nrContact: NRContact, zapMessage: String = "", amount: Double? = nil) {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        sendNotification(.lightningStrike, LightningStrike(location:strikeLocation, amount:selectedAmount, sideStrikeWidth: (availableWidth - (DIMENSIONS.PFP_BIG + 20.0))))
        withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
            activeColor = .yellow
        }
        cancellationId = UUID()
        SoundManager.shared.playThunderzap()
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrContact.pubkey, eTag: zapEtag, zapState: .initiated))
        QueuedFetcher.shared.enqueue(pTag: nrContact.pubkey) // Get latest wallet info to be sure (from kind:0)

        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            guard let cancellationId = cancellationId else { return }
            let zap = Zap(isNC:isNC, amount: Int64(selectedAmount), nrContact: nrContact, eventId: zapEtag, cancellationId: cancellationId, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
            nrContact.zapState = .initiated
        }
    }
}

struct ProfileZapButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadZaps()
        }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost("49635b590782cb1ab1580bd7e9d85ba586e6e99e48664bacf65e71821ae79df1") {
                    ProfileZapButton(nrContact: nrPost.contact, zapEtag: nrPost.id)
                }
                
                
//                Image("BoltIconActive").foregroundColor(.yellow)
//                    .padding(.horizontal, 10)
//                    .padding(.vertical, 5)
            }
        }
    }
}
