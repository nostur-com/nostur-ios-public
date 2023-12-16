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
    @State private var errorMessage:String? = nil
    private let paymentInfo:PaymentInfo
    
    init(paymentInfo:PaymentInfo) {
        self.paymentInfo = paymentInfo
    }
    
    private func amountSelected(amount:Double, zapMessage:String) {
        guard let account = account() else { return }
        guard let anyLud = paymentInfo.contact?.anyLud, anyLud == true else { return }
        let pubkey = paymentInfo.contact!.pubkey
        let eventId = paymentInfo.nrPost?.id ?? nil
        let relays = ConnectionPool.shared.connections.values
            .filter { $0.relayData.write }
            .map { $0.url }
        let isNC = account.isNC
        
        if (paymentInfo.supportsZap) {
            do {
                let zapRequestNote = zapRequest(forPubkey: pubkey, andEvent: eventId, withMessage: zapMessage, relays: relays)
                
                if isNC {
                    NSecBunkerManager.shared.requestSignature(forEvent: zapRequestNote, usingAccount: account, whenSigned: { signedZapRequestNote in
                        Task {
                            let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                            
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
                    
                    Task {
                        let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                        
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
                    let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amount * 1000))
                    
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
            ZapCustomizerSheet(name: (paymentInfo.nrPost?.anyName ?? paymentInfo.contact?.anyName) ?? "", supportsZap: paymentInfo.supportsZap, sendAction: { customZap in
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

