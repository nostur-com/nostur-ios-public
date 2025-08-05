//
//  ParticipantView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/07/2024.
//

import SwiftUI

struct NestParticipantView: View {
    
    @ObservedObject private var ss: SettingsStore = .shared
    @ObservedObject public var nrContact: NRContact
    public var role: String? = nil
    public let aTag: String
    public var disableZaps: Bool = false // This view can be loaded in multiple places at the same time, but it should only receive lightning strike in 1 place, pass disableZaps: true to avoid duplicate zaps
    
    public var showControls = true
    
    @State private var isZapped = false
    @State private var triggerStrike = false
    @State private var customAmount: Double? = nil
    @State private var zapMessage: String = ""
    
    var body: some View {
        VStack(spacing: 2.0) {
            ZappablePFP(pubkey: nrContact.pubkey, contact: nrContact, zapAtag: aTag)
                .onReceive(receiveNotification(.sendCustomZap)) { notification in
                    // Complete custom zap
                    guard !disableZaps else { return }
                    let customZap = notification.object as! CustomZap
                    guard customZap.customZapId == "LIVE-\(nrContact.pubkey)" else { return }
                    customAmount = customZap.amount
                    zapMessage = customZap.publicNote
                    triggerStrike = true
                }
                .overlay {
                    if triggerStrike && !disableZaps {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    guard !isZapped else { return }
                                    self.triggerZap(strikeLocation: geo.frame(in: .global).origin, nrContact: nrContact, zapMessage: zapMessage, amount: customAmount)
                                }
                        }
                    }
                }
//            PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                .overlay(alignment: .topLeading) {
                    if nrContact.raisedHand {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 35)) // Adjust size as needed
                            .foregroundColor(.orange) // Change the color as needed
                            .offset(x: -20.0, y: -12)
                            .rotationEffect(.degrees(-15))
                            .symbolEffectPulse()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showControls {
                        MicButton(volume: nrContact.volume, isMuted: nrContact.isMuted)
                            .offset(x: 15.0, y: 5)
                    }
                }
//                .overlay(alignment: .bottomLeading) {
//                    if nrContact.anyLud && showZapButton {
//                        NestZapButton(name: nrContact.anyName, aTag: aTag, nrContact: nrContact)
//                            .offset(x: -15.0, y: 5)
//                    }
//                }
            Text(nrContact.anyName).lineLimit(1)
            Text(role ?? "").font(.footnote)
                .foregroundColor(.secondary)
                .opacity(role != nil ? 1.0 : 0.0)
            
        }
        .onAppear {
            nrContact.listenForPresence(aTag)
        }
    }
    
    func triggerZap(strikeLocation: CGPoint, nrContact: NRContact, zapMessage: String = "", amount: Double? = nil) {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            sendNotification(.lightningStrike, LightningStrike(location: strikeLocation, amount: selectedAmount))
            SoundManager.shared.playThunderzap()
//            withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
//                activeColor = .yellow
//            }
        }
        let cancellationId = UUID() // We dont cancel on nests (because already have full sheet confirmation), but still cancellation id until we refactor api
        isZapped = true
        
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrContact.pubkey, aTag: aTag, zapState: .initiated))

        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC: isNC, amount: Int64(selectedAmount), nrContact: nrContact, aTag: aTag, cancellationId: cancellationId, zapMessage: zapMessage, withPending: true)
            NWCZapQueue.shared.sendZap(zap)
            Task { @MainActor in
                self.isZapped = false
                self.triggerStrike = false
                self.customAmount = nil
                self.zapMessage = ""
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        if let nrContact = PreviewFetcher.fetchNRContact() {
            let _ = nrContact.volume = 0.25
            NestParticipantView(nrContact: nrContact, role: "Moderator", aTag: "30311:07c058945239c541e7875ec21285e89d53afacc34a8e81b2c5ecdf028c198729:07056f33-cd48-4126-8b2e-ee68eeefafd9")
        }
    }
}


struct MicButton: View {
    public var volume: CGFloat
    public var isMuted: Bool
    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(Color.gray)
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottom) {
                    Color.accentColor
                        .frame(height: isMuted ? 0 : 28*(min(volume+(volume > 0.125 ? 0.25 : 0), 1.0)))
                        .animation(.interpolatingSpring(stiffness: 400, damping: 3), value: volume)
                }
                
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
        }
        .clipShape(Circle())
    }
}
