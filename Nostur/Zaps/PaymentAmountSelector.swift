//
//  PaymentAmountSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct PaymentAmountSelector: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String? = nil
    private let paymentInfo: PaymentInfo
    
    init(paymentInfo: PaymentInfo) {
        self.paymentInfo = paymentInfo
    }
    
    private func amountSelected(amount: Double, zapMessage: String) {
        
        // Fix: #0    (null) in Swift runtime failure: Double value cannot be converted to UInt64 because the result would be greater than UInt64.max ()
        guard (amount * 1000) <= Double(UInt64.max) else {
            L.og.error("🔴🔴 amount too large \(amount)")
            DispatchQueue.main.async {
                sendNotification(.anyStatus, ("Problem with amount", "APP_NOTICE"))
            }
            return
        }
        
        guard let account = account() else { return }
        guard let anyLud = paymentInfo.nrContact?.anyLud, anyLud == true else { return }
        let pubkey = paymentInfo.nrContact!.pubkey
        let eventId = (paymentInfo.nrPost?.id ?? paymentInfo.zapEtag) ?? nil
        let aTag = paymentInfo.zapAtag ?? nil
        let relays = ConnectionPool.shared.connections.values
            .filter { $0.relayData.write }
            .map { $0.url }
        let isNC = account.isNC
        
        if (paymentInfo.supportsZap) {
            do {
                let zapRequestNote = if let aTag {
                    zapRequest(forPubkey: pubkey, andATag: aTag, withMessage: zapMessage, relays: relays)
                }
                else {
                    zapRequest(forPubkey: pubkey, andEvent: eventId, withMessage: zapMessage, relays: relays)
                }
                
                if isNC {
                    NSecBunkerManager.shared.requestSignature(forEvent: zapRequestNote, usingAccount: account, whenSigned: { signedZapRequestNote in
                        Task {
                            
                            if paymentInfo.withPending, let aTag = paymentInfo.zapAtag {
                                DispatchQueue.main.async {
                                    sendNotification(.receivedPendingZap,
                                                     NRChatPendingZap(
                                                        id: signedZapRequestNote.id,
                                                        pubkey: signedZapRequestNote.publicKey,
                                                        createdAt: Date(timeIntervalSince1970: Double(signedZapRequestNote.createdAt.timestamp)),
                                                        aTag: aTag,
                                                        amount: Int64(amount),
                                                        nxEvent: NXEvent(pubkey: signedZapRequestNote.publicKey, kind: 9734),
                                                        content: NRContentElementBuilder.shared.buildElements(input: signedZapRequestNote.content, fastTags: signedZapRequestNote.fastTags).0
                                                     )
                                    )
                                }
                            }
                            
                            let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount: UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                            
                            if response.pr != nil {
                                await MainActor.run {
                                    if SettingsStore.shared.nwcReady {
                                        // NWC WALLET INSTANT ZAPS
                                        if nwcSendPayInvoiceRequest(response.pr!) {
                                            dismiss()
                                        }
                                        else {
                                            errorMessage = String(localized:"There was a problem, could not send sats", comment: "Error message")
                                        }
                                    }
                                    else {
                                        // OLD STYLE WALLET
                                        openURL(URL(string: "\(SettingsStore.shared.defaultLightningWallet.scheme)\(response.pr!)")!)
                                    }
                                }
                            }
                        }
                        
                    })
                }
                else {
                    let signedZapRequestNote = try account.signEvent(zapRequestNote)
                    
                    if paymentInfo.withPending, let aTag = paymentInfo.zapAtag {
                        DispatchQueue.main.async {
                            sendNotification(.receivedPendingZap,
                                             NRChatPendingZap(
                                                id: signedZapRequestNote.id,
                                                pubkey: signedZapRequestNote.publicKey,
                                                createdAt: Date(timeIntervalSince1970: Double(signedZapRequestNote.createdAt.timestamp)), aTag: aTag,
                                                amount: Int64(amount),
                                                nxEvent: NXEvent(pubkey: signedZapRequestNote.publicKey, kind: 9734), content: []
                                             ))
                        }
                    }
                    
                    Task {
                        let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount: UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                        
                        if response.pr != nil {
                            await MainActor.run {
                                if SettingsStore.shared.nwcReady {
                                    // NWC WALLET INSTANT ZAPS
                                    if nwcSendPayInvoiceRequest(response.pr!) {
                                        dismiss()
                                    }
                                    else {
                                        errorMessage = String(localized:"There was a problem, could not send sats", comment: "Error message")
                                    }
                                }
                                else {
                                 // OLD STYLE WALLET
                                    openURL(URL(string: "\(SettingsStore.shared.defaultLightningWallet.scheme)\(response.pr!)")!)
                                }
                            }
                        }
                        else {
                            L.og.error("🔴🔴 response.pr: Could not fetch invoice from: \(paymentInfo.callback)")
                            DispatchQueue.main.async {
                                sendNotification(.anyStatus, ("Could not fetch invoice from: \(paymentInfo.callback)", "APP_NOTICE"))
                            }
                        }
                    }
                }
            }
            catch {
                L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(paymentInfo.callback) \(error)")
            }
        }
        else {
            Task {
                do {
                    let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount: UInt64(amount * 1000))
                    
                    if response.pr != nil {
                        await MainActor.run {
                            if SettingsStore.shared.nwcReady {
                                // NWC WALLET INSTANT ZAPS
                                if nwcSendPayInvoiceRequest(response.pr!) {
                                    dismiss()
                                }
                                else {
                                    errorMessage = String(localized:"There was a problem, could not send sats", comment: "Error message")
                                }
                            }
                            else {
                             // OLD STYLE WALLET
                                openURL(URL(string: "\(SettingsStore.shared.defaultLightningWallet.scheme)\(response.pr!)")!)
                            }
                        }
                    }
                }
                catch {
                    L.fetching.notice("problem fetching ln invoice. callback:\(paymentInfo.callback) \(error)")
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            if let errorMessage {
                Text(errorMessage).fontWeight(.bold).foregroundColor(.red)
            }
            ZapCustomizerSheet(name: (paymentInfo.nrPost?.anyName ?? paymentInfo.nrContact?.anyName) ?? "", supportsZap: paymentInfo.supportsZap, sendAction: { customZap in
                amountSelected(amount:customZap.amount, zapMessage:customZap.publicNote)
            })
        }
    }
    
}

struct PaymentAmountSelector_Previews: PreviewProvider {
    static var previews: some View {
        let paymentInfo = PaymentInfo(min: 21, max: 1000000, callback: "", supportsZap: true)
        PreviewContainer {
            PaymentAmountSelector(paymentInfo: paymentInfo)
        }
    }
}

func mapLinearToExponential(value: Float, min: Float, max: Float, exponent: Float = 3) -> Float {
//    let exponent: Float = 3 // You can adjust this value to change the sensitivity

    let normalizedValue = (value - min) / (max - min)
    let exponentialValue = pow(normalizedValue, exponent)
    return min + (max - min) * exponentialValue
}

func mapExponentialToLinear(value: Float, min: Float, max: Float, exponent: Float = 3) -> Float {
    let normalizedValue = (value - min) / (max - min)
    let linearValue = pow(normalizedValue, 1/exponent)
    return min + (max - min) * linearValue
}

