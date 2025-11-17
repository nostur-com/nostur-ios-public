//
//  ZapButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import SwiftUI

// Zap button uses NWC if available, else just falls back to the old LightningButton
struct ZapButton: View, Equatable {

    static func == (lhs: ZapButton, rhs: ZapButton) -> Bool {
        lhs.nrPost.id == rhs.nrPost.id &&
        lhs.theme == rhs.theme
    }
    
    private let nrPost: NRPost
    private var isFirst: Bool
    private var isLast: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }

    var body: some View {
        ZapButtonInner(nrPost: nrPost, isFirst: isFirst, isLast: isLast, theme: theme)
    }
}

struct ZapButtonInner: View {
    private let nrPost: NRPost
    private var theme: Theme
    @ObservedObject private var footerAttributes: FooterAttributes
    @ObservedObject private var ss: SettingsStore = .shared
    @State private var cancellationId: UUID? = nil
    @State private var customZapId: String? = nil
    @State private var activeColor: Color? = nil
    @State private var isLoading = false
    
    
    @State private var triggerStrike = false
    @State private var customAmount: Double? = nil
    @State private var zapMessage: String = ""
    
    @State private var isZapped = false
    
    private var isFirst: Bool
    private var isLast: Bool
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
        self.theme = theme
    }
    
    private var icon: String {
        return if isLoading { "hourglass.tophalf.filled" }
               else if (isZapped || cancellationId != nil) { "bolt.fill"}
               else { "bolt" }
    }
    
    
    var body: some View {
//#if DEBUG
//        let _ = Self._printChanges()
//#endif
        Image(systemName: icon)
            .overlay(alignment: .leading) {
                if #available(iOS 26.0, *) {
                    Text(footerAttributes.zapTally, format: .number.notation((.compactName)))
                        .multilineTextAlignment(.center)
                        .animation(.snappy, value: footerAttributes.zapTally)
                        .contentTransition(.numericText(countsDown: false))
                        .opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                        .frame(width: 34)
                        .offset(x: 14)
                }
                else {
                    AnimatedNumberString(number: footerAttributes.zapTally.formatNumber)
                        .opacity(footerAttributes.zapTally == 0 ? 0 : 1)
                        .frame(width: 34)
                        .offset(x: 14)
                }
            }
            .padding(.trailing, 34)
            .foregroundColor(isZapped ? .yellow : theme.footerButtons)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in
                        if ss.nwcReady {
                            self.longTap()
                        }
                        else {
                            tap() 
                        }
                    }
            )
            .highPriorityGesture(
                TapGesture()
                    .onEnded { _ in
                        self.tap()
                    }
            )
            .onReceive(receiveNotification(.sendCustomZap)) { notification in
                // Complete custom zap
                let customZap = notification.object as! CustomZap
                guard customZapId != nil && customZap.customZapId == customZapId else { return }
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
                                guard cancellationId == nil else { return }
                                self.triggerZap(strikeLocation: geo.frame(in: .global).origin, nrContact: nrPost.contact, zapMessage: zapMessage, amount: customAmount)
                            }
                    }
                }
            }
            .onAppear {
                guard [.initiated, .nwcConfirmed, .zapReceiptConfirmed].contains(footerAttributes.zapState) else { return }
                isZapped = true
            }
            .onReceive(ViewUpdates.shared.zapStateChanged.receive(on: RunLoop.main)) { zapStateChange in
                guard nrPost.id == zapStateChange.eTag else { return }
                isZapped = [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapStateChange.zapState)
            }
    }
    
    private func tap() {
        if ss.nwcReady {
            if let cancellationId = cancellationId {
                cancelZap(cancellationId)
                triggerStrike = false
                SoundManager.shared.stop()
            }
            else if !isZapped, cancellationId == nil {
                triggerStrike = true
            }
        }
        else {
            nonNWCtap()
        }
    }
    
    private func longTap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        // Trigger custom zap
        customZapId = UUID().uuidString
        if let customZapId {
            sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: nrPost.anyName, customZapId: customZapId))
        }
    }
    
    func triggerZap(strikeLocation: CGPoint, nrContact: NRContact, zapMessage: String = "", amount: Double? = nil) {
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
        let cancellationId = UUID()
        self.cancellationId = cancellationId
        isZapped = true
        SoundManager.shared.playThunderzap()
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrPost.pubkey, eTag: nrPost.id, zapState: .initiated))
        QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey) // Get latest wallet info to be sure (from kind:0) 
        
        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC: isNC, amount: Int64(selectedAmount), nrContact: nrContact, eventId: nrPost.id, event: nrPost.event, cancellationId: cancellationId, zapMessage: zapMessage)
            NWCZapQueue.shared.sendZap(zap)
            accountCache()?.addZapped(nrPost.id)
        }
    }
    
    private func cancelZap(_ cancellationId: UUID) {
        self.cancellationId = nil
        footerAttributes.cancelZap(cancellationId)
        isZapped = false
        customAmount = nil
        zapMessage = ""
        activeColor = theme.footerButtons
        L.og.info("⚡️ Zap cancelled")
        bg().perform {
            accountCache()?.removeZapped(nrPost.id)
        }
        sendNotification(.postAction, PostActionNotification(type: .unzapped, eventId: nrPost.id))
    }
    
    private func nonNWCtap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard (nrPost.contact.anyLud) else { return }
        isLoading = true
        
        if let lud16 = nrPost.contact.lud16 {
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
                            if let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrPost.contact.zapperPubkeys.insert(zapperPubkey)
                            }
                            // Old zap sheet
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrPost: nrPost, nrContact: nrPost.contact)
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
        else if let lud06 = nrPost.contact.lud06 {
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
                            if let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrPost.contact.zapperPubkeys.insert(zapperPubkey)
                            }
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrPost: nrPost, nrContact: nrPost.contact)
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
                    ZapButton(nrPost: nrPost, theme: Themes.default.theme)
                }
                
                Image("BoltIconActive").foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
        }
    }
}
