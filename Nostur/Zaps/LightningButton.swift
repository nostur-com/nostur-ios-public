//
//  LightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct LightningButton: View {
    @EnvironmentObject var la:LoggedInAccount
    private let nrPost:NRPost
    @ObservedObject private var footerAttributes:FooterAttributes
    @State private var isLoading = false
    @State private var customZapId:UUID? = nil
    private var isFirst:Bool
    private var isLast:Bool
    
    init(nrPost: NRPost, isFirst: Bool = false, isLast: Bool = false) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.isFirst = isFirst
        self.isLast = isLast
    }
    
    var body: some View {
        if isLoading {
            Image(systemName: "hourglass.tophalf.filled")
                .padding(.vertical, 5)
        }
        else {
            Image("BoltIcon")
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    isLoading = true
                    buttonTapped()
                }
        }
    }
}

class PaymentInfo: Identifiable {
    var id = UUID()
    var min:UInt64 = 0
    var max:UInt64 = 5000000
    var callback = ""
    var supportsZap = false
    var nrPost:NRPost?
    var contact:Contact?
    
    init(min: UInt64, max: UInt64, callback: String = "", supportsZap: Bool = false, nrPost:NRPost? = nil, contact:Contact? = nil) {
        self.min = min
        self.max = max
        self.callback = callback
        self.supportsZap = supportsZap
        self.nrPost = nrPost
        self.contact = contact
    }
}

extension LightningButton {
    func buttonTapped() {
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

struct LightningButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadZaps()
        }) {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost("49635b590782cb1ab1580bd7e9d85ba586e6e99e48664bacf65e71821ae79df1") {
                    LightningButton(nrPost: nrPost)
                }
            }
        }
    }
}
