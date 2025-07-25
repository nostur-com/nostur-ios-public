//
//  LightningInvoice.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import SwiftUI

struct LightningInvoice: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var ss: SettingsStore = .shared
    public var invoice: String
    @State var divider :Double = 1 // 1 = SATS, 100000000 = BTC
    @State var fiatPrice = ""
    @State var cancellationId: UUID? = nil
    @State var activeColor = Color.red
    @State var isExpired: Bool = false
    @State var bolt11: Bolt11.Invoice? = nil
    
    var body: some View {
        VStack {
            if let bolt11 = bolt11 {
                Text("Bitcoin Lightning Invoice ⚡️", comment:"Title of a card that displays a lightning invoice").font(.caption)
                Divider()
                if let description = bolt11.description {
                    Text(description).font(.caption)
                        .padding(.bottom, 10)
                }
                Text("\(bolt11.amount != nil ? (Double(bolt11.amount!.int64)/divider).clean.description : "any") \(divider == 1 ? "sats" : "BTC") \(fiatPrice)")
                    .font(.title3).padding(.bottom, 10)
                    .onTapGesture {
                        divider = divider == 1 ? 100000000 : 1
                    }
                
                
                if ss.nwcReady && bolt11.amount != nil {
                    if let cancellationId {
                        // INSTANT ZAP TRIGGERED, CAN CANCEL
                        Button {
                            if Unpublisher.shared.cancel(cancellationId) {
                                NWCRequestQueue.shared.removeRequest(byCancellationId: cancellationId)
                            }
                            self.cancellationId = nil
                        } label: { Text(isExpired ? "Expired" : "Payment attempted").frame(minWidth: 150) }
                        .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                        .cornerRadius(20)
                        .disabled(isExpired)
                    }
                    else {
                        // BUTTON TO PAY INVOICE (DISABLED IF EXPIRED)
                        Text(isExpired ? "Expired" : "Pay")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundColor(isExpired ? Color.gray : Color.white)
                            .background(isExpired ? Color.gray.opacity(0.5) : theme.accent)
                            .cornerRadius(8)
                            .frame(minWidth: 150)
                            .overlay(
                                GeometryReader { geo in
                                    Color.white.opacity(0.001)
                                        .onTapGesture {
                                            guard !isExpired else { return }
                                            
                                            cancellationId = UUID()
                                            if nwcSendPayInvoiceRequest(invoice, cancellationId: cancellationId) {
                                                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                                impactMed.impactOccurred()
                                                sendNotification(.lightningStrike, LightningStrike(location:geo.frame(in: .global).origin, amount:Double(bolt11.amount!.int64)/divider))
                                                withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
                                                    activeColor = .yellow
                                                }
                                            }
                                            else {
                                                cancellationId = nil
                                                // TODO: feedback somehow
                                            }
                                        }
                                }
                            )
                    }
                }
                else {
                    // OLD STYLE WITHOUT NWC / INSTANT ZAPS
                    Button {
                        openURL(URL(string: "\(ss.defaultLightningWallet.scheme)\(invoice)")!)
                    } label: {
                        if isExpired {
                            Text("Expired", comment:"Button of an expired lightning invoice (disabled)").frame(minWidth: 150)
                        }
                        else {
                            Text("Pay", comment:"Button to pay a lightning invoice").frame(minWidth: 150)
                        }
                    }
                    .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                    .cornerRadius(20)
                    .disabled(isExpired)
                }
            }
            else {
                Text("Unable to decode lightning invoice", comment:"Error message")
            }
        }
        .padding(20)
        .background(LinearGradient(colors: isExpired ? [.gray, .black] : [.orange, .red],
                                   startPoint: .top,
                                   endPoint: .center).opacity(0.3))
        .cornerRadius(20)
        .task {
            Task {
                guard let bolt11 = Bolt11.decode(string: invoice) else { return }
                
                if let expiry = bolt11.expiry {
                    let isExpired = (bolt11.date + expiry) < .now
                    if isExpired != self.isExpired {
                        DispatchQueue.main.async {
                            self.bolt11 = bolt11
                            self.isExpired = isExpired
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.bolt11 = bolt11
                        }
                    }
                }
                else {
                    DispatchQueue.main.async {
                        self.bolt11 = bolt11
                    }
                }
            
                guard let amount = bolt11.amount else { return }
               
                self.fiatPrice = String(format: "($%.02f)",(Double(amount.int64) / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
            }
        }
        
    }
}

struct LightningInvoice_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            VStack {
//                let invoice = "lnbc469970n1p373e49pp5ey9mxfcy9k62clpjvqwsrju64p0378cll0mzehtccj2ulqnamkzqdqvw3jhxarfdenscqzpgxqyz5vqsp5m8zsyfs936f2vfkshvdfhntmr596079hwryr2r8dpr8ahy6hu6hq9qyyssqlcvvw6gmq09hwzw2kxfe03enc25plxzfmupxwx4xr8hddn972nzq7m0jf9sxenw23qg6nv55678nrnnr4fe3wkwm6pczmaxs0r7yftgqd6lgya"
                
                let invoice = "lnbc210n1pn6743vdp0f3jkzunwypek7mt9w35xjmn8yphx2aeqv4mx2uneypjxz7gnp4qtlkcwuavxr56fwplcqhl9sffrj78aw2c9tttkugc6g8unnq3wldwpp5n5v0w8stws5v9pw9mq2qrwrwxrfwxqphzlvgv6ph5dvhj0a5wprssp5jt3u7hydqyjj99rgg7gcj7ev8g9p64e98xnp4jg5d8egdg078crs9qyysgqcqpcxqyz5vqrzjqw9fu4j39mycmg440ztkraa03u5qhtuc5zfgydsv6ml38qd4azymlapyqqqqqqq86qqqqqlgqqqq86qqjqdrm6tcs55paj35nr32lw09qyz4qf2kzkrnnh2qjsf2ur7uaqqx6qf94kxsdzq0vpvn8790tndaee2rpyxgelzp4cvtmsd8y0f0f4n6cqrekyjg"
                
                VStack {
                    if let nrPost = { () -> NRPost? in
                        if let event = PreviewFetcher.fetchEvent() {
                            event.content = invoice
                            return NRPost(event: event)
                        }
                        return nil
                    }() {
                        PostRowDeletable(nrPost: nrPost)
                    }
                }
                .padding(10)
            }
            .withLightningEffect()
        }
    }
    
}
