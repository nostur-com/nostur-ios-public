import SwiftUI
import NostrEssentials

/// Just for testing things
struct NIP47TesterView: View {
    
    let TEST_PK = ""
    let TEST_LNINVOICE = ""
    
    var body: some View {
        @State var decodeTestText = ###"["EVENT","NWC",{"id":"65fdedf91ac75d599698d2851df2b0e12f1b418923b582a0b523f0f78f693175","pubkey":"69effe7b49a6dd5cf525bd0905917a5005ffe480b58eeb8e861418cf3ae760d9","created_at":1685888392,"kind":23195,"tags":[["p","1b5c3cfef0614ecf20f8f189f288341ed7c16ce55f64a58d73cbbe4ca044e81f"],["e","ee7a21ed83b293f11dafc86efe8117211da9140fff8a3c35087f67b298e8180c"]],"content":"hLCDxyeOP3GJdUtvOIVloDopQKVVaUUH0A6/PTkpqJJHvGQrIQHphl4iEO4+0d76onjFimsDz/mi1SmSkvFLeUUsPyCojiAHiU9xhY+4KWZZktcURTZP91ckYh8LF1SfLrZOxFe6KiCRiyEu3JM1illbtVxyTqtzMVFaLKMksi+HPwpFNGlS4yK9CDFIEhHI70Q8d7gWrdMVY/0M5UrmVAP2qmx7PThiYlTS2otbG+0=?iv=AJzKzR0PAi5Xi8KsVgxUWA==","sig":"c388dc5467d3ccd3afc7d93bdd111e460accf976a78b1d63dee65f92a71a58419d11164405f210d28c3b7bff514a9131f8da3cd80894e8719235b71fa13a170a"}]"###
        VStack {
            Button("decode test") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: decodeTestText, relay: "wss://relay.getalby.com/v1")
                }
                catch {
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1") else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                guard let decrypted = Keys.decryptDirectMessageContent(withPrivateKey: TEST_PK, pubkey: event.publicKey, content: event.content) else {
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
                if let keys = try? Keys(privateKeyHex: TEST_PK) {
                    
                    let request = NWCRequest(method: "pay_invoice", params: NWCRequest.NWCParams(invoice: TEST_LNINVOICE))
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var nwcReq = NEvent(content: requestJsonString)
                            nwcReq.kind = .nwcRequest
                            nwcReq.tags.append(NostrTag(["p", walletPubkey]))
                            
                            print(nwcReq.eventJson())
                            
                            guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex, pubkey: walletPubkey, content: nwcReq.content) else {
                                L.og.error("🔴🔴 Could not encrypt content")
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
                if let keys = try? Keys(privateKeyHex: "") {
                    //                let keys = NKeys.newKeys()
                    print("Public: \(keys.publicKeyHex)")
                    print("Private: \(keys.privateKeyHex)")
                    print("https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(keys.publicKeyHex)&return_to=nostur%3A%2F%2Fnwc_callback")
                    print("https://nwc.getalby.com/apps/new?c=Nostur&pubkey=\(keys.publicKeyHex)")
                }
            }
        }
    }
}

struct NIP47TesterView_Previews: PreviewProvider {
    static var previews: some View {
        NIP47TesterView()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
