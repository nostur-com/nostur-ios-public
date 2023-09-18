import SwiftUI

/// Just for testing things
struct NIP46TesterView: View {
    
    let TEST_PK = ""
            // pubkey = 16ff63e984b584702fe0749a2a6e7381c07a659a213f484d2af719703b64763a
    let TEST_LNINVOICE = ""
    
    var body: some View {
        @State var decodeTestText = ###"["EVENT","subby",{"id":"e5b25e152f37e5d8768afebca3ca48c3c353bff4f70319db51e514bb4fab3b72","pubkey":"f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027","created_at":1688065301,"kind":24133,"tags":[["p","16ff63e984b584702fe0749a2a6e7381c07a659a213f484d2af719703b64763a"]],"content":"mGjIar5KJ7L8bVb/EKXBlHcY6bHoQfSiAPDleDomg9bLqruh+7PsjlLoX5TZAW3HURC/kiYuo1Hf9Zr87AEptCIkC5zTeaLjdSrb92NeuUTo7RNfO1sNkod14E4bZV8p3XG1SW06kFe9c/6Jd6bztA==?iv=8ZM4TR24kvzI9+Cdq9fZBw==","sig":"82c9768c8dd25697ade270b1408f3d7acda8c0ea40d754255fe0d968c3fc95b948a4be0391aef48dbb9bfb2fb2746281ccf8a1f239c8bd86e08d4e78e73722d4"}]"###
        @State var decodeTestText2 = ###"["EVENT","subby",{"id":"f915c5ec5db8fffb87aba91dcc8a7b2decd9ba3d6658f5070c98b4dae643ba44","pubkey":"f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027","created_at":1688065679,"kind":24133,"tags":[["p","16ff63e984b584702fe0749a2a6e7381c07a659a213f484d2af719703b64763a"]],"content":"VkZ8sj8mW2HnC5Wo0jkyLy3vKCsA4uy5kUE/v7MCcp+oO5TTz2/YMHuN9cUhk0k7UdsPpZ8wx2JZTX7iRooTPUa4v14D8kpmKHgn8p3Kl/fBmtYmp5cdQgsclQLtETRq2cZnKcpmOyy3ocv3hnbJ2Zs7QrLXHft6uVt5R9UrtDQMedsiqHnsTLJ0OB+rKzfuoX5NxESCE7l6Ra3sSVVh6A==?iv=r/RQ7c1/EoXRiFKvMoGhlg==","sig":"edde04ba3f69d94785ba81e0dda817dc5950e3c1a1ecbde8630d2361b89475a388cb44bbaf2485edd7225fedd6126ac98b2c503d80b2266641a87018bebe2df8"}]"###
        
        @State var decodeTestText3 = ###"["EVENT","subby",{"id":"dbdbd2cd0f27a728814fd439ad73dc73ace851ff0c8859a854f850515ba0e64c","pubkey":"f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027","created_at":1688067385,"kind":24133,"tags":[["p","16ff63e984b584702fe0749a2a6e7381c07a659a213f484d2af719703b64763a"]],"content":"a0ag+WDWsQA1m6ECtdaY8RLPfFMVIgnSeerjvtZqN2inEjJdXhf6B7SCqNS8j8RyzoubXpnGYDW3H0vlOugKoDP89XiIGyL8X6Uk7txoxZIzqTv5bQzRTLiY+2D4Tg4JocZH2D2gXxaqSgBPvLX3YxWjLsh5s+sOu/S0gwXLdT0DVlOY5NBB9i6mNfn75pB0H12u0yA5cA/g541MhGummoQJG6CPzzDb6fmVG7sc+bwech9tYbphsryXxStvC1tjFXJgUgvwsv77W1E3K76qo1v3szxUNkFZ1rCKt/XvdebRmPGJpaCgVhUf9pYPTzvk/+FkkrwWk0EUs3njR/Tr1leuWTkfLXwrTdEYFSO3GjrHu8IrMdmSy2GSV9fzQB/Vy/AIuvvY81Xy+ue64rpuL19hwolXQyzauRYET/7TKnrmOBMAATBixWQxcbuxpaMZ20SIhbWS0nh+Sl7TVWDFnMOH4S3gyhk79HGtkElgL2iQ1QalRGAcSdx8nAbe8MQzIK7ag686yuqOHxq6lMBU75Nl8c2afpVWfX1jp5X6E9A=?iv=hYEafR4fXn9tKS81l7Jk3Q==","sig":"5d7b6d504870493a59aa22227757b0909af0c4efac27c735cc2bb3870c07a1df272fe0cbbec47250ceba1d39590b895f1adb50761f52e26dc909a14e0e2ae77f"}]"###
        
        @State var decodeAck = ###"["EVENT","NC",{"id":"9219d4163a0f1f2857afe0ead5bdde70a8b5cfa819982803a1d9aabcbff751be","pubkey":"f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027","created_at":1688100853,"kind":24133,"tags":[["p","16ff63e984b584702fe0749a2a6e7381c07a659a213f484d2af719703b64763a"]],"content":"t0qMySeRmFQsi7cFRgAQbf+jKrmLA7WkmealtYcsVWFwaNb8cS7dQtBr9ibkqEki?iv=X6/+Q8JliVtVDGFJdlPggg==","sig":"9631ec596f3ec2810076230baf4d46bb9113be60118e1b98c5d32bcb26b74a14dba907d776de9b008f786581189ddc21b98243d4813f645a7d6123b6e728f9fc"}]"###
        
        VStack {
            Button("decode test") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: decodeTestText, relay: "wss://memory")
                }
                catch {
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1") else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: TEST_PK, pubkey: event.publicKey, content: event.content) else {
                    print("Could not decrypt nwcResponse, \(event.eventJson())")
                    return
                }
                let decoder = JSONDecoder()
                guard let ncResponse = try? decoder.decode(NCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    print("Could not parse/decode ncResponse, \(event.eventJson()) - \(decrypted)")
                    return
                }
                if let error = ncResponse.error {
                    let message = "ncResponse error \(error)"
                    print(message)
                    return
                }
                guard let _ = ncResponse.result else {
                    print("Unknown or missing result \(decrypted)")
                    return
                }
                print(decrypted)
            }
            Button("decode test 2") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: decodeTestText2, relay: "wss://memory")
                }
                catch {
                    print("ffff")
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1") else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: TEST_PK, pubkey: event.publicKey, content: event.content) else {
                    print("Could not DECRYPT nwcResponse, \(event.eventJson())")
                    return
                }
                let decoder = JSONDecoder()
                guard let ncResponse = try? decoder.decode(NCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    print("Could not PARSE ncResponse")
                    print(event.eventJson())
                    print("---")
                    print(decrypted)
                    return
                }
                if let error = ncResponse.error {
                    print("ffff1")
                    let message = "ncResponse error \(error)"
                    print(message)
                    return
                }
                guard let result = ncResponse.result else {
                    print("Unknown or missing result \(decrypted)")
                    return
                }
                
                guard let resultArr = try? decoder.decode([String].self, from: result.data(using: .utf8)!) else {
                    print("Could not WHAT/decode ncResponse, \(event.eventJson()) - \(decrypted)")
                    return
                }
                
                print(decrypted)
                print(resultArr)
            }
            Button("decode test 3") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: decodeTestText3, relay: "wss://memory")
                }
                catch {
                    print("ffff")
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1") else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: TEST_PK, pubkey: event.publicKey, content: event.content) else {
                    print("Could not DECRYPT nwcResponse, \(event.eventJson())")
                    return
                }
                let decoder = JSONDecoder()
                guard let ncResponse = try? decoder.decode(NCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    print("Could not PARSE ncResponse")
                    print(event.eventJson())
                    print("---")
                    print(decrypted)
                    return
                }
                print(ncResponse.id)
                if let error = ncResponse.error {
                    print("ffff1")
                    let message = "ncResponse error \(error)"
                    print(message)
                    return
                }
                guard let result = ncResponse.result else {
                    print("Unknown or missing result \(decrypted)")
                    return
                }
       
                
                print(decrypted)
                print("----")
                print(result)
            }
            
            Button("decode ack") {
                var mmessage:RelayMessage? = nil
                do {
                    mmessage = try RelayMessage.parseRelayMessage(text: decodeAck, relay: "wss://memory")
                }
                catch {
                    print("ffff")
                    print(error)
                }
                guard let message = mmessage else { return }
//                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://relay.getalby.com/v1") else { print("fail1"); return }
                guard message.type == .EVENT, let event = message.event else { print("fail2"); return }
                 
                guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: TEST_PK, pubkey: event.publicKey, content: event.content) else {
                    print("Could not DECRYPT nwcResponse, \(event.eventJson())")
                    return
                }
                let decoder = JSONDecoder()
                guard let ncResponse = try? decoder.decode(NCResponse.self, from: decrypted.data(using: .utf8)!) else {
                    print("Could not PARSE ncResponse")
                    print(event.eventJson())
                    print("---")
                    print(decrypted)
                    return
                }
                if let error = ncResponse.error {
                    print("ffff1")
                    let message = "ncResponse error \(error)"
                    print(message)
                    return
                }
                guard let result = ncResponse.result else {
                    print("Unknown or missing result \(decrypted)")
                    return
                }
       
                
                print(decrypted)
                print("----")
                print(result)
            }
            
            Button("Connect") {
                let nsecBunkerPubkey = "f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027" // bunker managed key (Account.publicKey, but bunker has private key
                let token = ""
                if let keys = try? NKeys(privateKeyHex: TEST_PK) {
                    
                    let request = NCRequest(id: "connect-\(UUID().uuidString)", method: "connect", params: [keys.publicKeyHex(), token])
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var ncReq = NEvent(content: requestJsonString)
                            ncReq.kind = .ncMessage
                            ncReq.tags.append(NostrTag(["p", nsecBunkerPubkey]))
                            
                            print(ncReq.eventJson())
                            
                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: nsecBunkerPubkey, content: ncReq.content) else {
                                L.og.error("🔴🔴 Could not encrypt content")
                                return
                            }
                            
                            ncReq.content = encrypted
                            
                            if let signedReq = try? ncReq.sign(keys) {
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
            
            Button("get_public_key") {
                let nsecBunkerPubkey = "f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027"
                _ = ""
                if let keys = try? NKeys(privateKeyHex: TEST_PK) {
                    
                    let request = NCRequest(id: "get_public_key-1", method: "get_public_key", params: [])
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var ncReq = NEvent(content: requestJsonString)
                            ncReq.kind = .ncMessage
                            ncReq.tags.append(NostrTag(["p", nsecBunkerPubkey]))
                            
                            print(ncReq.eventJson())
                            
                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: nsecBunkerPubkey, content: ncReq.content) else {
                                L.og.error("🔴🔴 Could not encrypt content")
                                return
                            }
                            
                            ncReq.content = encrypted
                            
                            if let signedReq = try? ncReq.sign(keys) {
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
            
            Button("describe") {
                let nsecBunkerPubkey = "f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027"
                _ = ""
                if let keys = try? NKeys(privateKeyHex: TEST_PK) {
                    
                    let request = NCRequest(id: "describe-1", method: "describe", params: [])
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var ncReq = NEvent(content: requestJsonString)
                            ncReq.kind = .ncMessage
                            ncReq.tags.append(NostrTag(["p", nsecBunkerPubkey]))
                            
                            print(ncReq.eventJson())
                            
                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: nsecBunkerPubkey, content: ncReq.content) else {
                                L.og.error("🔴🔴 Could not encrypt content")
                                return
                            }
                            
                            ncReq.content = encrypted
                            
                            if let signedReq = try? ncReq.sign(keys) {
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
            
            Button("sign_event") {
                let nsecBunkerPubkey = "f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027"
                _ = ""
                if let keys = try? NKeys(privateKeyHex: TEST_PK) {
                    
                    var ncReq = NEvent(content: "ho ho ho")
                    ncReq.publicKey = "f3498f465b27ae48bd63850e3acda48a90eff80af829514034d11728d9a3a027"
                    ncReq.kind = .textNote
                    let ncReqWithId = ncReq.withId()
                    
                    let request = NCRequest(id: "sign_event-1", method: "sign_event", params: [ncReqWithId.eventJson()])
                    let encoder = JSONEncoder()
                    
                    if let requestJsonData = try? encoder.encode(request) {
                        if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                            var ncReq = NEvent(content: requestJsonString)
                            ncReq.kind = .ncMessage
                            ncReq.tags.append(NostrTag(["p", nsecBunkerPubkey]))
                            
                            print(ncReq.eventJson())
                            
                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: keys.privateKeyHex(), pubkey: nsecBunkerPubkey, content: ncReq.content) else {
                                L.og.error("🔴🔴 Could not encrypt content")
                                return
                            }
                            
                            ncReq.content = encrypted
                            
                            if let signedReq = try? ncReq.sign(keys) {
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
                let keys = NKeys.newKeys()
                print("Public: \(keys.publicKeyHex())")
                print("Private: \(keys.privateKeyHex())")
            }
        }
    }
}

struct NIP46TesterView_Previews: PreviewProvider {
    static var previews: some View {
        NIP46TesterView()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
