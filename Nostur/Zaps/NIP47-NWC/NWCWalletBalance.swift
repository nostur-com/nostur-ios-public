//
//  NWCWalletBalance.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/10/2023.
//

import SwiftUI
import NostrEssentials

struct NWCWalletBalance: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var ss:SettingsStore = .shared
    @ObservedObject private var nrq:NWCRequestQueue = .shared
    public var noIcon = false
    
    private func fiatPrice(_ amount:Double) -> String? {
        guard ExchangeRateModel.shared.bitcoinPrice > 0 else { return nil }
        return String(format: "($%.02f)",(amount / 100000000 * ExchangeRateModel.shared.bitcoinPrice))
    }

    var body: some View {
        if ss.nwcShowBalance && ss.nwcReady {
            switch nrq.balanceState {
            case .initial, .loading:
                ProgressView()
                    .task(id: "get_balance") {
                        do {
                            nwcSendBalanceRequest()
                            try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
                            if nrq.balanceState == .loading {
                                nrq.balanceState = .timeout
                            }
                        } catch {
                            
                        }
                    }
            case .ready(let balance, let sats):
                if noIcon {
                    Text("\(balance) sats \(sats != nil ? (fiatPrice(Double(sats!)) ?? "") : "")")
                        .onTapGesture {
                            nwcSendBalanceRequest()
                        }
                }
                else {
                    Text("\(Image(systemName:"bolt.fill")) \(balance) \(sats != nil ? (fiatPrice(Double(sats!)) ?? "") : "")")
                        .onTapGesture {
                            nwcSendBalanceRequest()
                        }
                }
            case .timeout:
                Image(systemName:"bolt.trianglebadge.exclamationmark.fill")
                    .opacity(0.5)
                    .onTapGesture {
                        nwcSendBalanceRequest()
                    }
            }
        }
        else {
            EmptyView()
        }
    }
}
    
func nwcSendBalanceRequest() {
    DispatchQueue.main.async {
#if DEBUG
        L.og.debug("⚡️ nwcSendBalanceRequest")
#endif
        let nrq = NWCRequestQueue.shared
        nrq.balanceState = .loading
        var pk:String?
        var walletPubkey:String?
        guard !SettingsStore.shared.activeNWCconnectionId.isEmpty else { L.og.error("⚡️ No activeNWCConnectionId"); return }
        guard let nwc = NWCConnection.fetchConnection(SettingsStore.shared.activeNWCconnectionId, context: DataProvider.shared().viewContext) else { L.og.error("⚡️ Problem fetching nwcConnection \(SettingsStore.shared.activeNWCconnectionId)"); return }
        
        guard let mainPK = nwc.privateKey else { L.og.error("⚡️ Problem with private key or nwcConnection"); return }
        pk = mainPK
        walletPubkey = nwc.walletPubkey
        
        guard let pk = pk else { return }
        guard let walletPubkey = walletPubkey else { return }
        
        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            
            DispatchQueue.main.async {
                if let keys = try? Keys(privateKeyHex: pk) {
                    
                    let request = NWCRequest(method: "get_balance")
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var nwcReq = NEvent(content: requestJsonString)
                            nwcReq.kind = .nwcRequest
                            nwcReq.tags.append(NostrTag(["p",walletPubkey]))
                            
#if DEBUG
                            L.og.debug("⚡️ Going to encrypt and send: \(nwcReq.eventJson())")
#endif
                            
                            guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: walletPubkey, content: nwcReq.content) else {
#if DEBUG
                                L.og.error("⚡️ Problem encrypting request")
#endif
                                return
                            }
                            
                            nwcReq.content = encrypted
                            
                            if let signedReq = try? nwcReq.sign(keys) {
                                Unpublisher.shared.publishNow(signedReq)
                                return
                            }
                            else {
#if DEBUG
                                L.og.error("⚡️ Problem signing: \(nwcReq.eventJson())")
#endif
                                return
                            }
                        }
                    }
                   
#if DEBUG
                    L.og.error("⚡️ Problem encoding request")
#endif
                    return
                }
            }
        }
    }
}


func balanceResponseHandled(_ nwcResponse:NWCResponse) -> Bool {
    guard let method = nwcResponse.result_type, method == "get_balance" else { return false }
    guard let result = nwcResponse.result, let balance = result.balance else { return false }
    DispatchQueue.main.async {
        NWCRequestQueue.shared.balance = balance / 1000
    }
    return true
}
