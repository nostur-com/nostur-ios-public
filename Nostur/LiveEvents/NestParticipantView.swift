//
//  ParticipantView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/07/2024.
//

import SwiftUI

struct NestParticipantView: View {
    
    @ObservedObject public var nrContact: NRContact
    public var role: String? = nil
    public let aTag: String
    
    public var showControls = true
    
    @State private var isZapped = false
    
    var body: some View {
        VStack(spacing: 2.0) {
            ZappablePFP(pubkey: nrContact.pubkey, contact: nrContact, zapAtag: aTag)
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
                    if showControls && nrContact.volume > 0 {
                        MicButton(volume: nrContact.volume, isMuted: nrContact.isMuted)
                            .offset(x: 15.0, y: 5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if nrContact.anyLud {
                        NestZapButton(name: nrContact.anyName, aTag: aTag, nrContact: nrContact)
                            .offset(x: -15.0, y: 5)
                    }
                }
                .onTapGesture {
                    navigateTo(nrContact)
                }
            Text(nrContact.anyName).lineLimit(1)
            Text(role ?? "").font(.footnote)
                .foregroundColor(.secondary)
                .opacity(role != nil ? 1.0 : 0.0)
            
        }
        .onAppear {
            nrContact.listenForPresence(aTag)
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
                        .frame(height: 28*(min(volume+(volume > 0.125 ? 0.25 : 0), 1.0)))
                        .animation(.interpolatingSpring(stiffness: 400, damping: 3), value: volume)
                }
                
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
        }
        .clipShape(Circle())
    }
}

struct NestZapButton: View {
    
    public var name: String
    public var aTag: String
    @ObservedObject public var nrContact: NRContact
    
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var customZapId: UUID? = nil
    @State private var activeColor: Color? = nil
    @State private var isLoading = false
    
    
    @State private var triggerStrike = false
    @State private var customAmount: Double? = nil
    @State private var zapMessage: String = ""
    
    @State private var isZapped = false
    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(Color.gray)
                .frame(width: 28, height: 28)
                
            Image(systemName: "bolt.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
        }
        .clipShape(Circle())
        .onTapGesture {
            self.tap()
        }
        .onReceive(receiveNotification(.sendCustomZap)) { notification in
            // Complete custom zap
            let customZap = notification.object as! CustomZap
            guard customZap.customZapId == customZapId else { return }
            customAmount = customZap.amount
            zapMessage = customZap.publicNote
            triggerStrike = true
        }
        .overlay {
            if triggerStrike {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            guard !isZapped else { return }
                            guard let contact = nrContact.contact else { return }
                            self.triggerZap(strikeLocation: geo.frame(in: .global).origin, contact: contact, zapMessage: zapMessage, amount: customAmount)
                        }
                }
            }
        }
    }
    
    private func tap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }

        if ss.nwcReady {
            // Trigger custom zap
            customZapId = UUID()
            if let customZapId {
                sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: name, customZapId: customZapId))
            }
        }
        else {
            nonNWCtap()
        }
    }
    
    func triggerZap(strikeLocation: CGPoint, contact: Contact, zapMessage: String = "", amount: Double? = nil) {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        sendNotification(.lightningStrike, LightningStrike(location: strikeLocation, amount: selectedAmount))
        withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
            activeColor = .yellow
        }
        let cancellationId = UUID() // We dont cancel on nests (because already have full sheet confirmation), but still cancellation id until we refactor api
        isZapped = true
        SoundManager.shared.playThunderzap()
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrContact.pubkey, aTag: aTag, zapState: .initiated))
        
        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC: isNC, amount: Int64(selectedAmount), contact: contact, aTag: aTag, cancellationId: cancellationId, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
            Task { @MainActor in
                self.isZapped = false
                self.triggerStrike = false
                self.customAmount = nil
                self.zapMessage = ""
            }
        }
    }
    
    private func nonNWCtap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard nrContact.anyLud else { return }
        isLoading = true
        
        if let lud16 = nrContact.lud16 {
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
                                nrContact.zapperPubkey = response.nostrPubkey!
                            }
                            // Old zap sheet
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: nrContact.mainContact)
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
        else if let lud06 = nrContact.lud06 {
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
                                nrContact.zapperPubkey = response.nostrPubkey!
                            }
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: nrContact.mainContact)
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
