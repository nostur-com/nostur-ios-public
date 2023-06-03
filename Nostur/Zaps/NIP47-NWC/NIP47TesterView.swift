//
//  NIP47TesterView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import SwiftUI

struct NIP47TesterView: View {
    var body: some View {
        @State var text = ###"["EVENT","04F429AE-AC49-427A-BA6A-F8DF1B55153E",{"id":"c7297407ca44e04507b93a9bc8405040a1b1832c448e9f92b7ee75cc77287f2a","pubkey":"69effe7b49a6dd5cf525bd0905917a5005ffe480b58eeb8e861418cf3ae760d9","created_at":1685763498,"kind":23195,"tags":[["p","9b374c36a01469aba0464b7c7bb9b317a5f252849c31ee2c4e8759a05acdacc4"],["e","24326be7d25ca1615bd4614ba2d2fedaf6ebe9b2d18ebc3480b41c80a60c608a"]],"content":"GikLVM/Adlhs+bTpU0Laap5ae72WGBzF4TW0aw1T82b9laOS3lV7C8nAsXDPg6R5LzPbHYtoDBuFIYERHfcVO7Ku4yrx9c0/qH8WuX7MotK4kwVTTMRFzHNdfvI14YLp?iv=3jFdORwKXde4EVxMYcEGcg==","sig":"726c49ac6e1a7e024cd1886dc29b40ec61a20ce9bc5e74a17b15f9897f808867eef7bd0e188e55699867bf3a09d83bd6da5fd828634670f08cdc0393a28b748e"}]"###
        VStack {
            Button("decode test") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1", skipValidation: true)
                }
                catch {
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1", skipValidation: true) else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                let pk = ""
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: event.publicKey, content: event.content) else {
                    print("Could not decrypt nwcResponse, \(event.eventJson())")
                    return
                }
                let decoder = JSONDecoder()
                guard let nwcResponse = try? decoder.decode(NWCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    print("Could not parse/decode nwcResponse, \(event.eventJson()) - \(decrypted)")
                    return
                }
                if let error = nwcResponse.error {
                    let message = "Zap failed \(error.message)"
                    print(message)
                    return
                }
                guard let result_type = nwcResponse.result_type, result_type == "pay_invoice" else {
                    print("Unknown or missing result_type, \(nwcResponse.result_type ?? "") - \(decrypted)")
                    return
                }
                print(decrypted)
            }
            Button("Send payment test") {
                let walletPubkey = "69effe7b49a6dd5cf525bd0905917a5005ffe480b58eeb8e861418cf3ae760d9"
//                let pubkey = "9b374c36a01469aba0464b7c7bb9b317a5f252849c31ee2c4e8759a05acdacc4"
                if let keys = try? NKeys(privateKeyHex: "") {
                    
                    let lninvoice = ""
                    let request = NWCRequest(method: "pay_invoice", params: NWCRequest.NWCParams(invoice: lninvoice))
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var nwcReq = NEvent(content: requestJsonString)
                            nwcReq.kind = .nwcRequest
                            nwcReq.tags.append(NostrTag(["p", walletPubkey]))
                            
                            print(nwcReq.eventJson())
                            
                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: walletPubkey, content: nwcReq.content) else {
                                print("🔴🔴 Could encrypt content")
                                return
                            }
                            
                            nwcReq.content = encrypted
                            
                            if let signedReq = try? nwcReq.sign(keys) {
                                print(signedReq.wrappedEventJson())
                                
                                // after send, should get
//                                [
//                                  "OK",
//                                  "bdd9129877cf7982e01d923bd52bc15ecfdf720c3d0e77012a04c7077d1af55d",
//                                  true,
//                                  ""
//                                ]
                            }
                        }
                    }
                }
            }
            
            Button("Create test keys") {
                if let keys = try? NKeys(privateKeyHex: "") {
                    //                let keys = NKeys.newKeys()
                    print("Public: \(keys.publicKeyHex())")
                    print("Private: \(keys.privateKeyHex())")
                    print("https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(keys.publicKeyHex())&return_to=nostur%3A%2F%2Fnwc_callback")
                    print("https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(keys.publicKeyHex())")
                }
            }
        }
    }
}

struct NIP47TesterView_Previews: PreviewProvider {
    static var previews: some View {
        NIP47TesterView()
            .previewDevice("iPhone 14")
    }
}
