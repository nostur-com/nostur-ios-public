// Relay Censorship Resistance
//1. Get all following pubkeys
//2. For Each pubkey, get write relays (from kind 3 or 10002)
//3. Group pubkeys by relays, now we have a list of relays, with pubkeys available on each relay
//4. Remove our own relay set from the list of relays
//
//A. Query these relays for new following messages
//    - A1 Create list of toQueryPubkeys, in the beginning it is equal to followingPubkeys
//    - Select Largest relay
//    - A2 Query relay, then substract queried pubkeys from toQueryPubkeys
//    - A3 if toQueryPubkeys is not empty, go to next relay, substract previous relay pubkeys from this one. repeat step A2
//
//B. When opening profile, always query a write relay that is not in our own set

//
//  Created by Fabian Lachman on 25/06/2023.
//

import SwiftUI

struct RelayIntelTest: View {
    
    @State var rcr:RelayCensorshipResistor? = nil
    let name = "hhu"
    
    
    var body: some View {
        VStack {
            //            Text("Hello {world}".replacingOccurrences(of: "{world}", with: "\(Image(systemName: "globe"))"))
            //
            //
            //            Text("A random text like this".replacingOccurrences(of: "this", with: "\(Image("BitcoinSymbol"))"))
            
            //            Text("omgdfj \(Text("\(Image("BitcoinSymbol"))").foregroundColor(.orange)) sdlfjlksd \(Image("HashtagBitcoin").resizable()) jfsd wtf huhhh \(Image(systemName: "globe")) \(name) boosted This is a test blabla ddiedo jasda d")
            
            Button("fetchRelays") {
                guard let rcr = rcr else { return }
                rcr.fetchRelays()
            }
            
            Button("pubkeysByWriteRelays") {
                guard let rcr = rcr else { return }
                //                print("keys: \(rcr?.followingPubkeys.count ?? 0)")
                //                print(rcr?.pubkeysByWriteRelays.description ?? "")
                //                for (key, value) in rcr.pubkeysByWriteRelays {
                //                    print("\(key): \(value.count)")
                //                }
                rcr.getKind3or10002s()
                
                let sortedDict = rcr.pubkeysByWriteRelaysMinusOurRelaySet.sorted { $0.value.count > $1.value.count }
                
                for (key, value) in sortedDict {
                    L.og.info("📡 \(key): \(value.count)")
                }
            }
        }
        .onAppear {
            var pubkeys = NosturState.shared.followingPublicKeys
            pubkeys.remove(NosturState.shared.activeAccountPublicKey)

            rcr = RelayCensorshipResistor(followingPubkeys: pubkeys)
        }
    }
}

typealias RelayAddress = String

// TODO: special handling for:
// wss://nostr.mutinywallet.com
// wss://purplepag.es

class RelayCensorshipResistor {
    private var backlog = Backlog(timeout: 60, auto: true)
    private var followingPubkeys:Set<ContactPubkey>
    private var ourRelaySet:[RelayAddress] {
        let sockets = SocketPool.shared.sockets.values
        let notNWC = sockets.filter { !$0.isNWC }
        let relayUrlStrings = notNWC.map { $0.url }
        let relayUrls = relayUrlStrings.compactMap { URL(string: $0)  }
        let ourRelaySet = relayUrls
            .filter { $0.scheme == "wss" && $0.host != nil }
            .map { "wss://\($0.host!)" }
        return ourRelaySet
    }
    
    var pubkeysByWriteRelays:[RelayAddress: Set<ContactPubkey>] = [:]
    
    var pubkeysByWriteRelaysMinusOurRelaySet:[RelayAddress: Set<ContactPubkey>] {
        pubkeysByWriteRelays.filter { !ourRelaySet.contains($0.key)  }
    }
    
    init(followingPubkeys: Set<String>) {
        self.followingPubkeys = followingPubkeys
    }
    
    public func fetchRelays() {
        var pubkeys = NosturState.shared.followingPublicKeys
        pubkeys.remove(NosturState.shared.activeAccountPublicKey)
        
        let reqTask = ReqTask(debounceTime: 5.0,
                              prefix: "3-10002",
                              reqCommand: { taskId in
            req(RM.getRelays(pubkeys: Array(pubkeys), subscriptionId: taskId))
        }, processResponseCommand: {  [weak self] taskId in
            guard let self = self else { return }
            L.og.info("📡 processResponseCommand")
            self.getKind3or10002s()
        }, timeoutCommand: { [weak self] taskId in
            guard let self = self else { return }
            L.og.info("📡 timeoutCommand")
            self.getKind3or10002s()
        })
        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func getKind3or10002s() {
        let decoder = JSONDecoder()
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind IN {3,10002} AND pubkey in %@", self.followingPubkeys)
        
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            if let kind3or10002s = try? DataProvider.shared().bg.fetch(fr) {
                L.og.info("📡 followingPubkeys: \(self.followingPubkeys.count) kind3or10002s's: \(kind3or10002s.count)")
                for k in kind3or10002s {
                    switch k.kind {
                    case 10002:
                        let rTags = k.fastTags.filter { $0.0 == "r" }
                        for r in rTags {
                            if let readOrWrite = r.2, readOrWrite == "write" {
                                guard let url = URL(string: r.1), let scheme = url.scheme,
                                      let host = url.host, scheme == "wss" else { continue }
                                
                                let key = "\(scheme)://\(host)"
                                
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                            
                            if r.2 == nil || r.2!.isEmpty {
                                guard let url = URL(string: r.1), let scheme = url.scheme,
                                      let host = url.host, scheme == "wss" else { continue }
                                
                                let key = "\(scheme)://\(host)"
                                
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                        }
                    case 3:
                        guard let content = k.content, let contentData = content.data(using: .utf8) else { continue }
                        guard let relays = try? decoder.decode(Kind3Relays.self, from: contentData) else { continue }
//                        if !relays.relays.isEmpty {
//                            L.og.info("📡 no relays for \(k.pubkey)")
//                        }
                        for relay in relays.relays {
                            guard let url = URL(string: relay.url), let scheme = url.scheme,
                                  let host = url.host, scheme == "wss" else { continue }
                            
                            let key = "\(scheme)://\(host)"
                            
                            if relay.readWrite.write ?? false {
                                if var existingRelay = self.pubkeysByWriteRelays[key] {
                                    existingRelay.insert(k.pubkey)
                                    self.pubkeysByWriteRelays[key] = existingRelay
                                }
                                else {
                                    self.pubkeysByWriteRelays[key] = [k.pubkey]
                                }
                            }
                        }
                    default:
                        L.og.debug("uhh")
                    }
                }
            }
        }
    }
}


struct RelayIntelTest_Previews: PreviewProvider {
    static var previews: some View {
        RelayIntelTest()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}


let followingPubkeysTest:Set<String> = [
    "e33fe65f1fde44c6dc17eeb38fdad0fceaf1cae8722084332ed1e32496291d42",
    "472f440f29ef996e92a186b8d320ff180c855903882e59d50de1b8bd5669301e",
    "a341f45ff9758f570a21b000c17d4e53a3a497c8397f26c0e6d61e5acffc7a98",
    "6e1534f56fc9e937e06237c8ba4b5662bcacc4e1a3cfab9c16d89390bec4fca3",
    "58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196",
    "26bd32c67232bdf16d05e763ec67d883015eb99fd1269025224c20c6cfdb0158",
    "c93406ed82c231019cf1d96700884fdedf1f7d5a32fa368b10b260cc6918f4a1",
    "d7f0e3917c466f1e2233e9624fbd6d4bd1392dbcfcaf3574f457569d496cb731",
    "3743244390be53473a7e3b3b8d04dce83f6c9514b81a997fb3b123c072ef9f78",
    "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245",
    "98315132d6ab8cfe404f3a8046b8336d545f1494b163b6ee6a6391c5aec248c9",
    "63fe6318dc58583cfe16810f86dd09e18bfd76aabc24a0081ce2856f330504ed",
    "08b80da85ba68ac031885ea555ab42bb42231fde9b690bbd0f48c128dfbf8009",
    "d91191e30e00444b942c0e82cad470b32af171764c2275bee0bd99377efd4075",
    "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52",
    "c1fc7771f5fa418fd3ac49221a18f19b42ccb7a663da8f04cbbf6c08c80d20b1",
    "04ea59bf576b9c41ad8d2137c538d4f499717bb3df14f5a20d9489dcc457774d",
    "dd663577f420383b0477d8117c709099904b45787bfe873ac1d366ee3f4cd75a",
    "0ab8ce60ed30f08679a23aba9ba629f76f1f9a9393184c2e4dc23b53224879d7",
    "bd27154882d5b052b91d16caa9c8a5925763a86185be037aac6d597b16eaa59b",
    "a305cc8926861bdde5c71bbb6fd394bb4cea6ef5f5f86402b249fc5ceb0ce220",
    "b9ce2f313bf6e7d116a89a82aed030eb782b06e34a8336acdda99906e841120e",
    "4ae44e9c794e7db01fd89233f338db732385b1d50ca8779cb8dcdd6c5de3a740",
    "bdb96ad31ac6af123c7683c55775ee2138da0f8f011e3994d56a27270e692575",
    "0ff244cca0eaab9e699693e44b3b18ebbdf674ee27d21d52a9702b57bb0a6d2b",
    "3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd",
    "ee11a5dff40c19a555f41fe42b48f00e618c91225622ae37b6c2bb67b76c4e49",
    "d987084c48390a290f5d2a34603ae64f55137d9b4affced8c0eae030eb222a25",
    "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
    "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93",
    "4523be58d395b1b196a9b8c82b038b6895cb02b683d0c253a955068dba1facd0",
    "ea09f3038a61d7af9bb59ae821ef80957fb2b9f3cb94ed4a6e2460cd51b90893",
    "021d7ef7aafc034a8fefba4de07622d78fd369df1e5f9dd7d41dc2cffa74ae02",
    "3d842afecd5e293f28b6627933704a3fb8ce153aa91d790ab11f6a752d44a42d",
    "6f35047caf7432fc0ab54a28fed6c82e7b58230bf98302bf18350ff71e10430a",
    "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0",
    "064de2497ce621aee2a5b4b926a08b1ca01bce9da85b0c714e883e119375140c",
    "3d2e51508699f98f0f2bdbe7a45b673c687fe6420f466dc296d90b908d51d594",
    "d8bcfacfcd875d196251b0e9fcd6932f960e22e45d3e6cc48c898917aa97645b",
    "1027fd5bc3b5e50c9800d48bc8acfbc290d89b857c7ce15572a57048c4c0558e",
    "a4cb51f4618cfcd16b2d3171c466179bed8e197c43b8598823b04de266cef110",
    "d26f78e5954117b5c6538a2d6c88a2296c65c038770399d7069a97826eb06a95",
    "826e9f895b81ab41a4522268b249e68d02ca81608def562a493cee35ffc5c759",
    "c49d52a573366792b9a6e4851587c28042fb24fa5625c6d67b8c95c8751aca15",
    "62fe02416353e9ac019c21f99b8288f53d1d29ea2d860653a67690d747d6e4ec",
    "1989034e56b8f606c724f45a12ce84a11841621aaf7182a1f6564380b9c4276b",
    "2ef93f01cd2493e04235a6b87b10d3c4a74e2a7eb7c3caf168268f6af73314b5",
    "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
    "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240",
    "50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63",
    "95361a2b42a26c22bac3b6b6ba4c5cac4d36906eb0cfb98268681c45a301c518",
    "330fb1431ff9d8c250706bbcdc016d5495a3f744e047a408173e92ae7ee42dac",
    "d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a",
    "b10c0000079a83cf26815dc7538818d8d56a2983e374e30a4143e50060978457",
    "dedf91f5c5eee3f3864eec34b28fc99c6a8cc44b250888ccf4d0d8d854f48d54",
    "f9a352db4aa115ec5d330540dda37b71e2460cc0f65e3318fa3b244945dc8eb8",
    "148d1366a5e4672b1321adf00321778f86a2371a4bdbe99133f28df0b3d32fa1",
    "bf943b7165fca616a483c6dc701646a29689ab671110fcddba12a3a5894cda15",
    "b708f7392f588406212c3882e7b3bc0d9b08d62f95fa170d099127ece2770e5e",
    "e8c1ca03a46d97184bfcd9125a5c9674a867bd1beaebe47c77d4eaec6c5ee874",
    "c48e29f04b482cc01ca1f9ef8c86ef8318c059e0e9353235162f080f26e14c11",
    "ed06a52841ed8ee544aed7a3f2156299881abb0a65e85fe0862e39e7208b2992",
    "577de06dce160a0379163a4bb7b680be3e0a0e1c68de6e6ba8c01134b44064dd",
    "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
    "7cb13cde0670e590f02cbe9ea0fcf1e05edbc5cc8a409731fa5436440181cf1d",
    "8eee8f5a002e533e9f9ffef14c713da449c23f56f4415e7995552075a02d1d37",
    "d376c4df7ee3ac69dcc88bedaee04e545c6ba190d2a710f05fa2c960f6bde9f3",
    "efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0",
    "2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884",
    "05e90eff47c1e0ecaf5c5bdd4cb25b96993728a68d8baf5fdd5ceb4e4c522648",
    "a1808558470389142e297d4729e081ab8bdff1ab50d0ebe22ffa78958f7a6ab7",
    "eaf27aa104833bcd16f671488b01d65f6da30163b5848aea99677cc947dd00aa",
    "b4cfa7ba658d88764e62dd0d40b6df3cc39d8a71fe1bd448a26b9253916e69cb",
    "1b11ed41e815234599a52050a6a40c79bdd3bfa3d65e5d4a2c8d626698835d6d",
    "e1ff3bfdd4e40315959b08b4fcc8245eaa514637e1d4ec2ae166b743341be1af",
    "460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c",
    "85a8679df872002a2701d93f908d9fa41d82c68a42a253ddb5b69c3881ad3f10",
    "e1055729d51e037b3c14e8c56e2c79c22183385d94aadb32e5dc88092cd0fef4",
    "f48cd1431fdb76ae9603c4fd6ad30f96643062d4d7a73a92cdce98d03dd15d13",
    "e9e4276490374a0daf7759fd5f475deff6ffb9b0fc5fa98c902b5f4b2fe3bba2",
    "9d065f84c0cba7b0ef86f5d2d155e6ce01178a8a33e194f9999b7497b1b2201b",
    "35d26e4690cbe1a898af61cc3515661eb5fa763b57bd0b42e45099c8b32fd50f",
    "883fea4c071fda4406d2b66be21cb1edaf45a3e058050d6201ecf1d3596bbc39",
    "5a8e581f16a012e24d2a640152ad562058cb065e1df28e907c1bfa82c150c8ba",
    "11b9a89404dbf3034e7e1886ba9dc4c6d376f239a118271bd2ec567a889850ce",
    "97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322",
    "743416b4943b20b8e1ed6c6d8fc81bbb7a27797c4cd3acafae4cc3d1ed67dd4d",
    "b9003833fabff271d0782e030be61b7ec38ce7d45a1b9a869fbdb34b9e2d2000",
    "8967f290cc7749fd3d232fb7110c05db746a31fce0635aeec4e111ad8bfc810d",
    "b99dbca0184a32ce55904cb267b22e434823c97f418f36daf5d2dff0dd7b5c27",
    "65b670a3cdd22bd7975c9c72d9a4cdb6243dbdb860f56b3f7b07a9cb65554931",
    "7b3f7803750746f455413a221f80965eecb69ef308f2ead1da89cc2c8912e968",
    "c9b19ffcd43e6a5f23b3d27106ce19e4ad2df89ba1031dd4617f1b591e108965",
    "be1d89794bf92de5dd64c1e60f6a2c70c140abac9932418fee30c5c637fe9479",
    "3eeb3de14ec5c48c6c4c9ff80908c4186170eabb74b2a6705a7db9f9922cd61e",
    "020f2d21ae09bf35fcdfb65decf1478b846f5f728ab30c5eaabcd6d081a81c3e",
    "ef151c7a380f40a75d7d1493ac347b6777a9d9b5fa0aa3cddb47fc78fab69a8b",
    "decaf1c5361563a0d6485db00692bc667e8344c3e6b3255556599e5d27fbdde5",
    "9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905",
    "ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc",
    "0b39c4074924b4bd13202f642628e1a55cff411a904cc17394263c0df0b9686c",
    "52b4a076bcbbbdc3a1aefa3735816cf74993b1b8db202b01c883c58be7fad8bd",
    "82d70f9685eabec271201bacd1fc1941e9686a9bf2b686c381a5b662f60002b1",
    "bb1cf5250435ff475cd8b32acb23e3ee7bbe8fc38f6951704b4798513947672c",
    "7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194",
    "df173277182f3155d37b330211ba1de4a81500c02d195e964f91be774ec96708",
    "1739d937dc8c0c7370aa27585938c119e25c41f6c441a5d34c6d38503e3136ef",
    "489ac583fc30cfbee0095dd736ec46468faa8b187e311fda6269c4e18284ed0c",
    "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9",
    "7f5c2b4e48a0e9feca63a46b13cdb82489f4020398d60a2070a968caa818d75d",
    "e8d67c435a4a59304e1414280e952efe17be4254fca27916bf63f9f73e54aba4",
    "0931b81d12be6881dd4a70fbc0ac606db4392ca32465daf6de74bdec4ea18c08",
    "d2704392769c20d67a153fa77a8557ab071ef27aafc29cf6b46faf582e0595f2",
    "b495341b7b78b18839200fd293f861433602f16cb3d1e569d87dce1656ced9e1",
    "4379e76bfa76a80b8db9ea759211d90bb3e67b2202f8880cc4f5ffe2065061ad",
    "72f9755501e1a4464f7277d86120f67e7f7ec3a84ef6813cc7606bf5e0870ff3",
    "2779f3d9f42c7dee17f0e6bcdcf89a8f9d592d19e3b1bbd27ef1cffd1a7f98d1",
    "b17c59874dc05d7f6ec975bce04770c8b7fa9d37f3ad0096fdb76c9385d68928",
    "00000000827ffaa94bfea288c3dfce4422c794fbb96625b6b31e9049f729d700",
    "9c163c7351f8832b08b56cbb2e095960d1c5060dd6b0e461e813f0f07459119e",
    "da1a336379dd61d16d90468031efca9520dbd3dfc31f66c172d2a4ec7aab2c74",
    "74ffc51cc30150cf79b6cb316d3a15cf332ab29a38fec9eb484ab1551d6d1856",
    "a5e93aef8e820cbc7ab7b6205f854b87aed4b48c5f6b30fbbeba5c99e40dcf3f",
    "10c90242e7700a28479430bb82b13a2bb317186d91c79bce11974266a560c019",
    "3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
    "d12feb34b3ee120423b818cd8dda47000639bbec9a6ee6d3317ea886ec5b084f",
    "27797bd4e5ee52db0a197668c92b9a3e7e237e1f9fa73a10c38d731c294cfc9a",
    "c6209b5936aea5092e677e3817b25329e1fb5f206ea8b8e97c59d4ab35ac6e0c",
    "001892e9b48b430d7e37c27051ff7bf414cbc52a7f48f451d857409ce7839dde",
    "51b826cccd92569a6582e20982fd883fccfa78ad03e0241f7abec1830d7a2565",
    "b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc",
    "50a25300cc08675d90d834475405a7f16668c0f2f1c2238b2ce9fc43d13b6646",
    "090254801a7e8e5085b02e711622f0dfa1a85503493af246aa42af08f5e4d2df",
    "76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa",
    "6c237d8b3b120251c38c230c06d9e48f0d3017657c5b65c8c36112eb15c52aeb",
    "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204",
    "9579444852221038dcba34512257b66a1c6e5bdb4339b6794826d4024b3e4ce9",
    "fdd5e8f6ae0db817be0b71da20498c1806968d8a6459559c249f322fa73464a7",
    "6ad08392d1baa3f6ff7a9409e2ac5e5443587265d8b4a581c6067d88ea301584",
    "eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f",
    "0a722ca20e1ccff0adfdc8c2abb097957f0e0bf32db18c4281f031756d50eb8d",
    "aef0d6b212827f3ba1de6189613e6d4824f181f567b1205273c16895fdaf0b23",
    "f5fd754857046f37eae58c982d7a0991ba08c996f5b3390fa2bad47ef2718ded",
    "19fefd7f39c96d2ff76f87f7627ae79145bc971d8ab23205005939a5a913bc2f",
    "076161ca22da5a2ab8c74465cbf08f79f3e7e8bb31f4dc211bd94319ebade03d",
    "388c7fba25af828bc1020314b798e1cfb5e8431d451b244a9d48fd4a1ac0697c",
    "54fc669ccc03a47b3d95a9111bfddc590863d26a398c7149d2d349683b8451c8",
    "ff04a0e6cd80c141b0b55825fed127d4532a6eecdb7e743a38a3c28bf9f44609",
    "1bc70a0148b3f316da33fe3c89f23e3e71ac4ff998027ec712b905cd24f6a411",
    "9a39bf837c868d61ed8cce6a4c7a0eb96f5e5bcc082ad6afdd5496cb614a23fb",
    "bae77874946ec111f94be59aef282de092dc4baf213f8ecb8c9e15cb7ed7304e",
    "5be6446aa8a31c11b3b453bf8dafc9b346ff328d1fa11a0fa02a1e6461f6a9b1",
    "8dec0c55eb078c623eb849ddf00208c252fbfa02da30851dfb0f3027497d714b",
    "5a9c48c8f4782351135dd89c5d8930feb59cb70652ffd37d9167bf922f2d1069",
    "eaf1a13a032ce649bc60f290a000531c4d525f6a7a28f74326972c4438682f56",
    "7560e065bdfe91872a336b4b15dacd2445257f429364c10efc38e6e7d8ffc1ff",
    "91c9a5e1a9744114c6fe2d61ae4de82629eaaa0fb52f48288093c7e7e036f832",
    "36c24dafa66fc420000bb3c1b5380eee010b642316a65e6bf8a5aba30edd3ce5",
    "78688c1f371e7b923d95368c9298cca06c1ec0a89ea897aa181bd60091121fea",
    "b9a537523bba2fcdae857d90d8a760de4f2139c9f90d986f747ce7d0ec0d173d",
    "c7d32972e398d4d20cd69b1a8451956cc14a2e9065ad1a8fda185c202698937b",
    "68ead3b4880e72e8025f75cd1d4bc8f39b9736167a16485cf4f81ec5d6165080",
    "612af115a6196b16585a30695cfd3f4fae6c7c95d01407602c12495f0011810c",
    "e88a691e98d9987c964521dff60025f60700378a4879180dcbbb4a5027850411",
    "045745ac0e90a436141a3addd95575c2ead47b613f45287283e5802ff7fd99fd",
    "29fbc05acee671fb579182ca33b0e41b455bb1f9564b90a3d8f2f39dee3f2779",
    "ccaa9ef229e14fee5732af621325ca6993bc079f6e816dee01d94b0e9c74c15b",
    "8766a54ef9a170b3860bc66fd655abb24b5fda75d7d7ff362f44442fbdeb47b9",
    "387519cafd325668ecffe59577f37238638da4cf2d985b82f932fc81d33da1e8",
    "7ef1d9f80efcbe8c879e38bde4a24016fca93c7874a22a6e4a8b5062bfed835e",
    "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9",
    "c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0",
    "b3cf6e9274d5f6509187ff13c74556d22b2042f7b77df3ef6e0f1d13fb412cc0",
    "f728d9e6e7048358e70930f5ca64b097770d989ccd86854fe618eda9c8a38106",
    "9be0b18d150e22f4545249ecdfe8b93b75948ce5d3063b009679dfdda4f5626d",
    "edcd20558f17d99327d841e4582f9b006331ac4010806efa020ef0d40078e6da",
    "05933d8782d155d10cf8a06f37962f329855188063903d332714fbd881bac46e",
    "bb9f02a1fc7c8384e449660933eacfb158fdc4c7e4a981f99daf8ffb409024b4",
    "23b1a71c129ef53fdcf85f81dc20a017cf1ef421b7e5649c84bcdddf673bed43",
    "c7dccba4fe4426a7b1ea239a5637ba40fab9862c8c86b3330fe65e9f667435f6",
    "8fe3f243e91121818107875d51bca4f3fcf543437aa9715150ec8036358939c5",
    "8685ebef665338dd6931e2ccdf3c19d9f0e5a1067c918f22e7081c2558f8faf8"
]
