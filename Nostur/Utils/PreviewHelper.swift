//
//  PreviewHelper.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/01/2023.
//

import SwiftUI
import CoreData
import NostrEssentials

let PREVIEW_ACCOUNT_ID = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
let PREVIEW_DEVICE = "iPhone 15"

public class PreviewEnvironment {
    
    var didLoad = false
    let er:ExchangeRateModel = .shared
    let dim:DIMENSIONS = .shared
    let sm:SideBarModel = .shared
    let themes:Themes = .default
    let kind0:Kind0Processor = .shared
    let npn:NewPostNotifier = NewPostNotifier.shared
    let cp:ConnectionPool = ConnectionPool.shared
    
    static let shared = PreviewEnvironment()
        
    let userDefaults:UserDefaults = {
        let d = UserDefaults(suiteName: "preview_user_defaults")!
        d.set(PREVIEW_ACCOUNT_ID, forKey: "activeAccountPublicKey")
        d.set(true, forKey: "devToggle")
        d.set("Following", forKey: "selected_subtab")
        d.set("Main", forKey: "selected_tab")
        d.set(false, forKey: "full_width_images")
        d.set(FOOTER_BUTTONS_PREVIEW, forKey: "footer_buttons")
        return d
    }()
    
    let ss:SettingsStore = .shared
    
    let vmc:ViewModelCache = .shared
    
    let context:NSManagedObjectContext = DataProvider.shared().container.viewContext
    let decoder = JSONDecoder()
    
    init() { }
    
//    var didParseMessages = false
    public func parseMessages(_ messages:[String]) {
//        guard !didParseMessages else { return }
//        didParseMessages = true
        // TODO: Should reuse Importer.shared
        context.performAndWait {
            for text in messages {
                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://memory") else { continue }
                guard var event = message.event else { continue }
                
                // FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
                if event.kind == .repost && event.content.prefix(2) == #"{""# {
                    if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                        _ = Event.saveEvent(event: noteInNote, context: context)
                        event.content = "#[0]"
                        if let firstTag = event.tags.first {
                            if firstTag.type == "e" {
                                event.tags[0] = NostrTag(["e", firstTag.id, "", "mention"])
                            }
                        }
                    }
                }
                
                let savedEvent = Event.saveEvent(event: event, context: context)
                
                if event.kind == .setMetadata {
                    Contact.saveOrUpdateContact(event: event)
                }
                
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if event.kind == .zapNote {
                    Event.updateZapTallyCache(savedEvent, context: context)
                }
            }
        }
    }
    
    public func parseNoDbMessages(_ messages: [String]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for text in messages {
                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://memory") else { continue }
                guard message.event != nil else { continue }

                DispatchQueue.main.async {
                    sendNotification(.receivedMessage, message)
                }
            }
        }
    }
}

extension PreviewEnvironment {
    
    @MainActor func loadAccount() -> Bool {
//        guard !didLoad else { return false }
//        didLoad = true
//        NRState.shared.loadAccounts()
        context.performAndWait {
            print("💄💄LOADING ACCOUNT")
            let account = CloudAccount(context: self.context)
            account.flags = "full_account"
            account.createdAt = Date()
            account.publicKey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            account.name = "Fabian"
            account.nip05 = "fabian@nostur.com"
            account.about = "Creatur of Nostur"
            account.picture = "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972"
            account.banner = "https://profilepics.nostur.com/banner_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/banner.jpg?1682440972"
            account.followingPubkeys = ["2edbcea694d164629854a52583458fd6d965b161e3c48b57d3aff01940558884",
                                        "787338757fc25d65cd929394d5e7713cf43638e8d259e8dcf5c73b834eb851f2",
                                        "134743ca8ad0203b3657c20a6869e64f160ce48ae6388dc1f5ca67f346019ee7",
                                        "8dec0c55eb078c623eb849ddf00208c252fbfa02da30851dfb0f3027497d714b",
                                        "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204",
                                        "388c7fba25af828bc1020314b798e1cfb5e8431d451b244a9d48fd4a1ac0697c",
                                        "126103bfddc8df256b6e0abfd7f3797c80dcc4ea88f7c2f87dd4104220b4d65f",
                                        "07c058945239c541e7875ec21285e89d53afacc34a8e81b2c5ecdf028c198729",
                                        "0cf08d280aa5fcfaf340c269abcf66357526fdc90b94b3e9ff6d347a41f090b7",
                                        "be1d89794bf92de5dd64c1e60f6a2c70c140abac9932418fee30c5c637fe9479",
                                        "f1989a96d75aa386b4c871543626cbb362c03248b220dc9ae53d7cefbcaaf2c1",
                                        "6f2d7f00a955d9aecdc4cb38ef0f9e2fa758df010974f165be4d1670bb5bb577",
                                        "37fbbf7707e70a8a7787e5b1b75f3e977e70aab4f41ddf7b3c0f38caedd875d4",
                                        "98315132d6ab8cfe404f3a8046b8336d545f1494b163b6ee6a6391c5aec248c9",
                                        "08b80da85ba68ac031885ea555ab42bb42231fde9b690bbd0f48c128dfbf8009",
                                        "c1fc7771f5fa418fd3ac49221a18f19b42ccb7a663da8f04cbbf6c08c80d20b1",
                                        "b2d670de53b27691c0c3400225b65c35a26d06093bcc41f48ffc71e0907f9d4a",
                                        "883fea4c071fda4406d2b66be21cb1edaf45a3e058050d6201ecf1d3596bbc39",
                                        "3d2e51508699f98f0f2bdbe7a45b673c687fe6420f466dc296d90b908d51d594",
                                        "266815e0c9210dfa324c6cba3573b14bee49da4209a9456f9484e5106cd408a5",
                                        "26bd32c67232bdf16d05e763ec67d883015eb99fd1269025224c20c6cfdb0158",
                                        "d26f78e5954117b5c6538a2d6c88a2296c65c038770399d7069a97826eb06a95",
                                        "de7ecd1e2976a6adb2ffa5f4db81a7d812c8bb6698aa00dcf1e76adb55efd645",
                                        "51b826cccd92569a6582e20982fd883fccfa78ad03e0241f7abec1830d7a2565",
                                        "89e14be49ed0073da83b678279cd29ba5ad86cf000b6a3d1a4c3dc4aa4fdd02c",
                                        "d987084c48390a290f5d2a34603ae64f55137d9b4affced8c0eae030eb222a25",
                                        "001892e9b48b430d7e37c27051ff7bf414cbc52a7f48f451d857409ce7839dde",
                                        "7560e065bdfe91872a336b4b15dacd2445257f429364c10efc38e6e7d8ffc1ff",
                                        "ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc",
                                        "d49a9023a21dba1b3c8306ca369bf3243d8b44b8f0b6d1196607f7b0990fa8df",
                                        "52b4a076bcbbbdc3a1aefa3735816cf74993b1b8db202b01c883c58be7fad8bd",
                                        "05933d8782d155d10cf8a06f37962f329855188063903d332714fbd881bac46e",
                                        "bd27154882d5b052b91d16caa9c8a5925763a86185be037aac6d597b16eaa59b",
                                        "97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322",
                                        "7f5c2b4e48a0e9feca63a46b13cdb82489f4020398d60a2070a968caa818d75d",
                                        "f1725586a402c06aec818d1478a45aaa0dc16c7a9c4869d97c350336d16f8e43",
                                        "aa746c026c3b37de2c9a721fbf8e110235ffbb35f99620002d9ff60edebe9986",
                                        "d8bcfacfcd875d196251b0e9fcd6932f960e22e45d3e6cc48c898917aa97645b",
                                        "c5cfda98d01f152b3493d995eed4cdb4d9e55a973925f6f9ea24769a5a21e778",
                                        "f288a224a61b7361aa9dc41a90aba8a2dff4544db0bc386728e638b21da1792c",
                                        "c48e29f04b482cc01ca1f9ef8c86ef8318c059e0e9353235162f080f26e14c11",
                                        "8766a54ef9a170b3860bc66fd655abb24b5fda75d7d7ff362f44442fbdeb47b9",
                                        "5a8e581f16a012e24d2a640152ad562058cb065e1df28e907c1bfa82c150c8ba",
                                        "47c0002b0214be2c5460053f0c63ffb44c0881efffb44e464a3df2d9dbc46376",
                                        "826e9f895b81ab41a4522268b249e68d02ca81608def562a493cee35ffc5c759",
                                        "0931b81d12be6881dd4a70fbc0ac606db4392ca32465daf6de74bdec4ea18c08",
                                        "8c430bdaadc1a202e4dd11c86c82546bb108d755e374b7918181f533b94e312e",
                                        "aef0d6b212827f3ba1de6189613e6d4824f181f567b1205273c16895fdaf0b23",
                                        "a6a22d58db6709e81c5717667dbee2ddbac22448575dabf92f4b30c6ee1129f1",
                                        "3c07d68edf71f6d22374dffae054e6801468594e7b0d0625fb5bcd24b202264d",
                                        "1739d937dc8c0c7370aa27585938c119e25c41f6c441a5d34c6d38503e3136ef",
                                        "c6209b5936aea5092e677e3817b25329e1fb5f206ea8b8e97c59d4ab35ac6e0c",
                                        "e8d67c435a4a59304e1414280e952efe17be4254fca27916bf63f9f73e54aba4",
                                        "bb1cf5250435ff475cd8b32acb23e3ee7bbe8fc38f6951704b4798513947672c",
                                        "decaf1c5361563a0d6485db00692bc667e8344c3e6b3255556599e5d27fbdde5",
                                        "8ea485266b2285463b13bf835907161c22bb3da1e652b443db14f9cee6720a43",
                                        "7339d2b6814b6be916a45b87a4077bb72c61dc6d9e8052ee39462f626e0d1fc7",
                                        "9020fe7857bd2392d504beeb9e568776f507784fb5b5a94af7b5ef1ae9780289",
                                        "c8df6ae886c711b0e87adf24da0181f5081f2b653a61a23b1055a36022293a06",
                                        "36732cc35fe56185af1b11160a393d6c73a1fe41ddf1184c10394c28ca5d627b",
                                        "e9e4276490374a0daf7759fd5f475deff6ffb9b0fc5fa98c902b5f4b2fe3bba2",
                                        "021d7ef7aafc034a8fefba4de07622d78fd369df1e5f9dd7d41dc2cffa74ae02",
                                        "04ea59bf576b9c41ad8d2137c538d4f499717bb3df14f5a20d9489dcc457774d",
                                        "b9d02cb8fddeb191701ec0648e37ed1f6afba263e0060fc06099a62851d25e04",
                                        "62fe02416353e9ac019c21f99b8288f53d1d29ea2d860653a67690d747d6e4ec",
                                        "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
                                        "0b39c4074924b4bd13202f642628e1a55cff411a904cc17394263c0df0b9686c",
                                        "0962a7d6342862955d6b9bacb068bd7eb4a0aa88c052c7e7050a496c1d5ca915",
                                        "9be0b18d150e22f4545249ecdfe8b93b75948ce5d3063b009679dfdda4f5626d",
                                        "85a8679df872002a2701d93f908d9fa41d82c68a42a253ddb5b69c3881ad3f10",
                                        "c89cf36deea286da912d4145f7140c73495d77e2cfedfb652158daa7c771f2f8",
                                        "00000000827ffaa94bfea288c3dfce4422c794fbb96625b6b31e9049f729d700",
                                        "bf943b7165fca616a483c6dc701646a29689ab671110fcddba12a3a5894cda15",
                                        "fe7f6bc6f7338b76bbf80db402ade65953e20b2f23e66e898204b63cc42539a3",
                                        "460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c",
                                        "3f68dede81549cc0844fafe528f1574b51e095e7491f468bd9689f87779bb81d",
                                        "d0debf9fb12def81f43d7c69429bb784812ac1e4d2d53a202db6aac7ea4b466c",
                                        "c2622c916d9b90e10a81b2ba67b19bdfc5d6be26c25756d1f990d3785ce1361b",
                                        "e417ee3d910253993ae0ce6b41d4a24609970f132958d75b2d9b634d60a3cc08",
                                        "b9ceaeeb4178a549e8b0570f348b2caa4bef8933fe3323d45e3875c01919a2c2",
                                        "f9a352db4aa115ec5d330540dda37b71e2460cc0f65e3318fa3b244945dc8eb8",
                                        "b9ce2f313bf6e7d116a89a82aed030eb782b06e34a8336acdda99906e841120e",
                                        "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
                                        "d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a",
                                        "3335d373e6c1b5bc669b4b1220c08728ea8ce622e5a7cfeeb4c0001d91ded1de",
                                        "7b3f7803750746f455413a221f80965eecb69ef308f2ead1da89cc2c8912e968",
                                        "0a403270cede202c2429bd69171524ca56c2e1c891729b83748594cc0c628253",
                                        "eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f",
                                        "b3cf6e9274d5f6509187ff13c74556d22b2042f7b77df3ef6e0f1d13fb412cc0",
                                        "69a161f62b0df32d7c606193a4f6cd5b7cb42be2790efe97f9b6ebf8a748b53c",
                                        "f728d9e6e7048358e70930f5ca64b097770d989ccd86854fe618eda9c8a38106",
                                        "577de06dce160a0379163a4bb7b680be3e0a0e1c68de6e6ba8c01134b44064dd",
                                        "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9",
                                        "b9a537523bba2fcdae857d90d8a760de4f2139c9f90d986f747ce7d0ec0d173d",
                                        "74ffc51cc30150cf79b6cb316d3a15cf332ab29a38fec9eb484ab1551d6d1856",
                                        "da1a336379dd61d16d90468031efca9520dbd3dfc31f66c172d2a4ec7aab2c74",
                                        "045745ac0e90a436141a3addd95575c2ead47b613f45287283e5802ff7fd99fd",
                                        "7cc328a08ddb2afdf9f9be77beff4c83489ff979721827d628a542f32a247c0e",
                                        "17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4",
                                        "bfc058c9abb250a2f4f0f240210ae750221b614f19b9872ea8cdf59a69d68914",
                                        "11b9a89404dbf3034e7e1886ba9dc4c6d376f239a118271bd2ec567a889850ce",
                                        "82d70f9685eabec271201bacd1fc1941e9686a9bf2b686c381a5b662f60002b1",
                                        "ff04a0e6cd80c141b0b55825fed127d4532a6eecdb7e743a38a3c28bf9f44609",
                                        "b9003833fabff271d0782e030be61b7ec38ce7d45a1b9a869fbdb34b9e2d2000",
                                        "5c508c34f58866ec7341aaf10cc1af52e9232bb9f859c8103ca5ecf2aa93bf78",
                                        "6ad08392d1baa3f6ff7a9409e2ac5e5443587265d8b4a581c6067d88ea301584",
                                        "ee6ea13ab9fe5c4a68eaf9b1a34fe014a66b40117c50ee2a614f4cda959b6e74",
                                        "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0",
                                        "05e90eff47c1e0ecaf5c5bdd4cb25b96993728a68d8baf5fdd5ceb4e4c522648",
                                        "50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63",
                                        "d376c4df7ee3ac69dcc88bedaee04e545c6ba190d2a710f05fa2c960f6bde9f3",
                                        "edcd20558f17d99327d841e4582f9b006331ac4010806efa020ef0d40078e6da",
                                        "8eee8f5a002e533e9f9ffef14c713da449c23f56f4415e7995552075a02d1d37",
                                        "e1ff3bfdd4e40315959b08b4fcc8245eaa514637e1d4ec2ae166b743341be1af",
                                        "1c52ebc82654e443f92501b7d0ca659e78b75fddcb9c5a65f168ec945698c92a",
                                        "7cb13cde0670e590f02cbe9ea0fcf1e05edbc5cc8a409731fa5436440181cf1d",
                                        "8967f290cc7749fd3d232fb7110c05db746a31fce0635aeec4e111ad8bfc810d",
                                        "0ab8ce60ed30f08679a23aba9ba629f76f1f9a9393184c2e4dc23b53224879d7",
                                        "58c741aa630c2da35a56a77c1d05381908bd10504fdd2d8b43f725efa6d23196",
                                        "4379e76bfa76a80b8db9ea759211d90bb3e67b2202f8880cc4f5ffe2065061ad",
                                        "1b11ed41e815234599a52050a6a40c79bdd3bfa3d65e5d4a2c8d626698835d6d",
                                        "4523be58d395b1b196a9b8c82b038b6895cb02b683d0c253a955068dba1facd0",
                                        "2ef93f01cd2493e04235a6b87b10d3c4a74e2a7eb7c3caf168268f6af73314b5",
                                        "b708f7392f588406212c3882e7b3bc0d9b08d62f95fa170d099127ece2770e5e",
                                        "facdaf1ce758bdf04cdf1a1fa32a3564a608d4abc2481a286ffc178f86953ef0",
                                        "a305cc8926861bdde5c71bbb6fd394bb4cea6ef5f5f86402b249fc5ceb0ce220",
                                        "3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd",
                                        "36c24dafa66fc420000bb3c1b5380eee010b642316a65e6bf8a5aba30edd3ce5",
                                        "63fe6318dc58583cfe16810f86dd09e18bfd76aabc24a0081ce2856f330504ed",
                                        "3743244390be53473a7e3b3b8d04dce83f6c9514b81a997fb3b123c072ef9f78",
                                        "2779f3d9f42c7dee17f0e6bcdcf89a8f9d592d19e3b1bbd27ef1cffd1a7f98d1",
                                        "4ea843d54a8fdab39aa45f61f19f3ff79cc19385370f6a272dda81fade0a052b",
                                        "d2704392769c20d67a153fa77a8557ab071ef27aafc29cf6b46faf582e0595f2",
                                        "eaf1a13a032ce649bc60f290a000531c4d525f6a7a28f74326972c4438682f56",
                                        "1248b16acbc663d62a0cfa43f7e7c5cd6ab9c2c6db3e1b6378f01e6c2e20ed4b",
                                        "d91191e30e00444b942c0e82cad470b32af171764c2275bee0bd99377efd4075",
                                        "472f440f29ef996e92a186b8d320ff180c855903882e59d50de1b8bd5669301e",
                                        "9579444852221038dcba34512257b66a1c6e5bdb4339b6794826d4024b3e4ce9",
                                        "c49d52a573366792b9a6e4851587c28042fb24fa5625c6d67b8c95c8751aca15",
                                        "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
                                        "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9",
                                        "1577e4599dd10c863498fe3c20bd82aafaf829a595ce83c5cf8ac3463531b09b",
                                        "a5e93aef8e820cbc7ab7b6205f854b87aed4b48c5f6b30fbbeba5c99e40dcf3f",
                                        "7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194",
                                        "76c71aae3a491f1d9eec47cba17e229cda4113a0bbb6e6ae1776d7643e29cafa",
                                        "cbc5ef6b01cbd1ffa2cb95a954f04c385a936c1a86e1bb9ccdf2cf0f4ebeaccb",
                                        "8fe3f243e91121818107875d51bca4f3fcf543437aa9715150ec8036358939c5",
                                        "40b9c85fffeafc1cadf8c30a4e5c88660ff6e4971a0dc723d5ab674b5e61b451",
                                        "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52",
                                        "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93",
                                        "053935081a69624466034446eda3374d905652ddbf8217c88708182687a33066",
                                        "98636ad321a02cce6415803dc0da34ff8fe364330acf943740a304ad71065260",
                                        "bf2376e17ba4ec269d10fcc996a4746b451152be9031fa48e74553dde5526bce",
                                        "ccaa9ef229e14fee5732af621325ca6993bc079f6e816dee01d94b0e9c74c15b",
                                        "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e",
                                        "e88a691e98d9987c964521dff60025f60700378a4879180dcbbb4a5027850411",
                                        "a4cb51f4618cfcd16b2d3171c466179bed8e197c43b8598823b04de266cef110",
                                        "b99dbca0184a32ce55904cb267b22e434823c97f418f36daf5d2dff0dd7b5c27",
                                        "e1055729d51e037b3c14e8c56e2c79c22183385d94aadb32e5dc88092cd0fef4",
                                        "148d1366a5e4672b1321adf00321778f86a2371a4bdbe99133f28df0b3d32fa1",
                                        "ad9d42203fd2480ea2e5c4c64593a027708aebe2b02aa60bd7b1d666daa5b08d",
                                        "6f35047caf7432fc0ab54a28fed6c82e7b58230bf98302bf18350ff71e10430a",
                                        "5be6446aa8a31c11b3b453bf8dafc9b346ff328d1fa11a0fa02a1e6461f6a9b1",
                                        "347e56e8185507e0543f70ae84bb97cf5f4f23ad4782daacd437ac53a1519634",
                                        "bae77874946ec111f94be59aef282de092dc4baf213f8ecb8c9e15cb7ed7304e",
                                        "489ac583fc30cfbee0095dd736ec46468faa8b187e311fda6269c4e18284ed0c",
                                        "fdd5e8f6ae0db817be0b71da20498c1806968d8a6459559c249f322fa73464a7",
                                        "65b670a3cdd22bd7975c9c72d9a4cdb6243dbdb860f56b3f7b07a9cb65554931",
                                        "95361a2b42a26c22bac3b6b6ba4c5cac4d36906eb0cfb98268681c45a301c518",
                                        "387519cafd325668ecffe59577f37238638da4cf2d985b82f932fc81d33da1e8",
                                        "3129509e23d3a6125e1451a5912dbe01099e151726c4766b44e1ecb8c846f506",
                                        "6ad3e2a34818b153c81f48c58f44e5199e7b4fc8dbe37810a000dce3c90b7740",
                                        "1989034e56b8f606c724f45a12ce84a11841621aaf7182a1f6564380b9c4276b",
                                        "27797bd4e5ee52db0a197668c92b9a3e7e237e1f9fa73a10c38d731c294cfc9a",
                                        "078c0c78a35e6d3bc290a8e0097144e1d7c471815f23e8cfa1b082b80b5424d4",
                                        "ee11a5dff40c19a555f41fe42b48f00e618c91225622ae37b6c2bb67b76c4e49",
                                        "5a9c48c8f4782351135dd89c5d8930feb59cb70652ffd37d9167bf922f2d1069",
                                        "b10c0000079a83cf26815dc7538818d8d56a2983e374e30a4143e50060978457",
                                        "b5b26195bafa17b6c7cbe0100b2918ec3c5e168ce4f40337de76f5072fcf04a7",
                                        "0d0547de422dfbc821247725bfc761c3efd11da98f6fef0ec3dc213465155c5a",
                                        "6c237d8b3b120251c38c230c06d9e48f0d3017657c5b65c8c36112eb15c52aeb",
                                        "50a25300cc08675d90d834475405a7f16668c0f2f1c2238b2ce9fc43d13b6646",
                                        "9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905",
                                        "3eeb3de14ec5c48c6c4c9ff80908c4186170eabb74b2a6705a7db9f9922cd61e",
                                        "b495341b7b78b18839200fd293f861433602f16cb3d1e569d87dce1656ced9e1",
                                        "28c64522edc6f3555c8abc6df7992c354fac4894885900518307b2d4cfb90206",
                                        "da42dcb3946c398ff0699c2ab8903db9f8e967d16e084c279999ae1980a52fa4",
                                        "c9b19ffcd43e6a5f23b3d27106ce19e4ad2df89ba1031dd4617f1b591e108965",
                                        "dedf91f5c5eee3f3864eec34b28fc99c6a8cc44b250888ccf4d0d8d854f48d54",
                                        "72f9755501e1a4464f7277d86120f67e7f7ec3a84ef6813cc7606bf5e0870ff3",
                                        "b83a28b7e4e5d20bd960c5faeb6625f95529166b8bdb045d42634a2f35919450",
                                        "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240",
                                        "e8c1ca03a46d97184bfcd9125a5c9674a867bd1beaebe47c77d4eaec6c5ee874",
                                        "a341f45ff9758f570a21b000c17d4e53a3a497c8397f26c0e6d61e5acffc7a98",
                                        "9c163c7351f8832b08b56cbb2e095960d1c5060dd6b0e461e813f0f07459119e",
                                        "78688c1f371e7b923d95368c9298cca06c1ec0a89ea897aa181bd60091121fea",
                                        "19fefd7f39c96d2ff76f87f7627ae79145bc971d8ab23205005939a5a913bc2f",
                                        "eeadea6cbb5018a190f0117857de513cc271d24c947d56cd82c54a6b64ae47a4",
                                        "218238431393959d6c8617a3bd899303a96609b44a644e973891038a7de8622d",
                                        "0ff244cca0eaab9e699693e44b3b18ebbdf674ee27d21d52a9702b57bb0a6d2b",
                                        "0a722ca20e1ccff0adfdc8c2abb097957f0e0bf32db18c4281f031756d50eb8d",
                                        "c93406ed82c231019cf1d96700884fdedf1f7d5a32fa368b10b260cc6918f4a1",
                                        "090254801a7e8e5085b02e711622f0dfa1a85503493af246aa42af08f5e4d2df",
                                        "efc37e97fa4fad679e464b7a6184009b7cc7605aceb0c5f56b464d2b986a60f0",
                                        "9c33d279c9a48af396cc159c844534e5f38e5d114667748a62fa33ffbc57b653",
                                        "f45f5667ffe7649d7c9f648930c9498cda88974e7ea28929194d0167cdcbc124",
                                        "c37b6a82a98de368c104bbc6da365571ec5a263b07057d0a3977b4c05afa7e63",
                                        "e76450df94f84c1c0b71677a45d75b7918f0b786113c2d038e6ab8841b99f276",
                                        "c4eabae1be3cf657bc1855ee05e69de9f059cb7a059227168b80b89761cbc4e0",
                                        "1bdeb7c42c558c1cc286d7b46e464acbfa83df7b58987cadfbeacc83fb4b9d91",
                                        "330fb1431ff9d8c250706bbcdc016d5495a3f744e047a408173e92ae7ee42dac",
                                        "ef151c7a380f40a75d7d1493ac347b6777a9d9b5fa0aa3cddb47fc78fab69a8b",
                                        "ff27d01cb1e56fb58580306c7ba76bb037bf211c5b573c56e4e70ca858755af0",
                                        "813fce4c4e76f1e7b4f4697bf1030a90f1a0b783f187d329800a4dd8697f9759",
                                        "19dcd48f846e6623d5264e601c41dcbe184eacdae6d6da191cc9b81a97947bcd",
                                        "b17c59874dc05d7f6ec975bce04770c8b7fa9d37f3ad0096fdb76c9385d68928",
                                        "54fc669ccc03a47b3d95a9111bfddc590863d26a398c7149d2d349683b8451c8",
                                        "c7d32972e398d4d20cd69b1a8451956cc14a2e9065ad1a8fda185c202698937b",
                                        "922945779f93fd0b3759f1157e3d9fa20f3fd24c4b8f2bcf520cacf649af776d",
                                        "bbd2da1b871a6ee6dad21f8f0836fbf0db2224bebde40197b8733dee19fc624e",
                                        "91c9a5e1a9744114c6fe2d61ae4de82629eaaa0fb52f48288093c7e7e036f832",
                                        "3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24",
                                        "eaf27aa104833bcd16f671488b01d65f6da30163b5848aea99677cc947dd00aa",
                                        "49792b0c3e803bb97f4005f83a8d6c09a58c6ea7f04e1ab19d149f9fabbbcee3",
                                        "7ef1d9f80efcbe8c879e38bde4a24016fca93c7874a22a6e4a8b5062bfed835e",
                                        "f5fd754857046f37eae58c982d7a0991ba08c996f5b3390fa2bad47ef2718ded",
                                        "29fbc05acee671fb579182ca33b0e41b455bb1f9564b90a3d8f2f39dee3f2779",
                                        "3e294d2fd339bb16a5403a86e3664947dd408c4d87a0066524f8a573ae53ca8e",
                                        "c1fe52f8f5f40415e8237711ae4369fd4ecf753c995b512f49a1b26b8da18569",
                                        "79c2cae114ea28a981e7559b4fe7854a473521a8d22a66bbab9fa248eb820ff6",
                                        "031cdf9461f7688b8ccca79d3dfe99ba14ebcafe79d8486add306c8e3c51ee3f",
                                        "ea09f3038a61d7af9bb59ae821ef80957fb2b9f3cb94ed4a6e2460cd51b90893",
                                        "23b1a71c129ef53fdcf85f81dc20a017cf1ef421b7e5649c84bcdddf673bed43",
                                        "020f2d21ae09bf35fcdfb65decf1478b846f5f728ab30c5eaabcd6d081a81c3e",
                                        "c465a1051794a507a55adebc0f044dc6e79d9b67a5e05aed4bf684afe088f976",
                                        "2183e94758481d0f124fbd93c56ccaa45e7e545ceeb8d52848f98253f497b975",
                                        "bb9f02a1fc7c8384e449660933eacfb158fdc4c7e4a981f99daf8ffb409024b4",
                                        "1027fd5bc3b5e50c9800d48bc8acfbc290d89b857c7ce15572a57048c4c0558e",
                                        "5e313964c2ef226a67a7c68ac7d7d30249136eaea93e5978e782e0fe43e7f4ef",
                                        "9fec72d579baaa772af9e71e638b529215721ace6e0f8320725ecbf9f77f85b1",
                                        "9a39bf837c868d61ed8cce6a4c7a0eb96f5e5bcc082ad6afdd5496cb614a23fb",
                                        "6faf0104f3e2ce74d4e9775d72d3657b0f4da9c10bb3666346b86a3749cd7d08",
                                        "604e96e099936a104883958b040b47672e0f048c98ac793f37ffe4c720279eb2",
                                        "90590edc247b100f23879a412b6616c65e874ac790610a15e6b3257a18d9ae43",
                                        "e33fe65f1fde44c6dc17eeb38fdad0fceaf1cae8722084332ed1e32496291d42",
                                        "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245",
                                        "bdb96ad31ac6af123c7683c55775ee2138da0f8f011e3994d56a27270e692575",
                                        "8685ebef665338dd6931e2ccdf3c19d9f0e5a1067c918f22e7081c2558f8faf8",
                                        "35d26e4690cbe1a898af61cc3515661eb5fa763b57bd0b42e45099c8b32fd50f",
                                        "df173277182f3155d37b330211ba1de4a81500c02d195e964f91be774ec96708",
                                        "726a1e261cc6474674e8285e3951b3bb139be9a773d1acf49dc868db861a1c11",
                                        "efa6abd09142caf23dfb70ed3b9bd549042901caa66f686259a1cc55a4970369",
                                        "3d842afecd5e293f28b6627933704a3fb8ce153aa91d790ab11f6a752d44a42d",
                                        "1bc70a0148b3f316da33fe3c89f23e3e71ac4ff998027ec712b905cd24f6a411",
                                        "b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc",
                                        "064de2497ce621aee2a5b4b926a08b1ca01bce9da85b0c714e883e119375140c",
                                        "f48cd1431fdb76ae9603c4fd6ad30f96643062d4d7a73a92cdce98d03dd15d13",
                                        "a3eb29554bd27fca7f53f66272e4bb59d066f2f31708cf341540cb4729fbd841",
                                        "c7dccba4fe4426a7b1ea239a5637ba40fab9862c8c86b3330fe65e9f667435f6",
                                        "7bdef7be22dd8e59f4600e044aa53a1cf975a9dc7d27df5833bc77db784a5805"]
            NRState.shared.loadAccount(account)
            SettingsStore.shared.webOfTrustLevel = "WOT_OFF"
//            return account
        }
        return true
    }
    
    @MainActor func loadAccounts() {
        context.performAndWait {
            let account = CloudAccount(context: self.context)
            account.flags = "full_account"
            account.createdAt = Date()
            account.publicKey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            account.name = "Fabian"
            account.nip05 = "fabian@nostur.com"
            account.about = "Creatur of Nostur"
            account.picture = "https://profilepics.nostur.com/profilepic_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/profilepic.jpg?1682440972"
            account.banner = "https://profilepics.nostur.com/banner_v1/e358d89477e2303af113a2c0023f6e77bd5b73d502cf1dbdb432ec59a25bfc0f/banner.jpg?1682440972"
            
            let account2 = CloudAccount(context: self.context)
            account2.createdAt = Date()
            account2.publicKey = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
            account2.name = "Rookie"
            account2.about = "Second account"
            
            let account3 = CloudAccount(context: self.context)
            account3.createdAt = Date()
            account3.publicKey = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"
            account3.name = "Explorer"
            account3.about = "Third account"
            
            do {
                
                let account4keys = try Keys.newKeys()
                let account4 = CloudAccount(context: self.context)
                account4.createdAt = Date()
                account4.flags = "full_account"
                account4.publicKey = account4keys.publicKeyHex
                account4.privateKey = account4keys.privateKeyHex
                account4.name = "The Poster"
                account4.about = "4th account, with private key"
                
                let account5keys = try Keys.newKeys()
                let account5 = CloudAccount(context: self.context)
                account5.flags = "full_account"
                account5.createdAt = Date()
                account5.publicKey = account5keys.publicKeyHex
                account5.privateKey = account5keys.privateKeyHex
                account5.name = "Alt"
                account5.about = "5th account, with private kay"
                
                let account6keys = try Keys.newKeys()
                let account6 = CloudAccount(context: self.context)
                account6.flags = "full_account"
                account6.createdAt = Date()
                account6.publicKey = account6keys.publicKeyHex
                account6.privateKey = account6keys.privateKeyHex
                account6.name = "Alt"
                account6.about = "6th account, with private kay"
                
                let account7keys = try Keys.newKeys()
                let account7 = CloudAccount(context: self.context)
                account7.flags = "full_account"
                account7.createdAt = Date()
                account7.publicKey = account7keys.publicKeyHex
                account7.privateKey = account7keys.privateKeyHex
                account7.name = "Alt"
                account7.about = "5th account, with private kay"
                
                NRState.shared.accounts = [account, account2, account3, account4, account5, account6, account7]
            } catch { }
        }
//        NRState.shared.loadAccounts()
        
        if let account = NRState.shared.accounts.first {
            NRState.shared.loadAccount(account)
        }
    }
    
    func loadContacts() {
        context.performAndWait {
            self.parseMessages(testKind0Events())
        }
    }   
    func loadChats() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let messages = testChats()
            for text in messages {
                guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://memory") else { continue }
                guard message.event != nil else { continue }

                DispatchQueue.main.async {
                    sendNotification(.receivedMessage, message)
                }
            }
        }
    }
    
    func loadContactLists() {
        context.performAndWait {
            self.parseMessages(testKind3Events())
        }
    }
    
    func loadPosts() {
        context.performAndWait {
            self.parseMessages(testKind1Events())
//            self.parseMessages(testSnowden())
        }
    }

    func loadReposts() {
        context.performAndWait {
            self.parseMessages(testKind6Events())
        }
    }
    
    func loadKind1063() {
        context.performAndWait {
            self.parseMessages(testKind1063())
        }
    }
    
    func loadHighlights() {
        context.performAndWait {
            self.parseMessages(testHighlights())
        }
    }
    
    func loadBadges() {
        context.performAndWait {
            self.parseMessages(testBadges())
        }
    }
    
    func loadDMs() {
        context.performAndWait {
            self.parseMessages(testDMs())
        }
    }
        
    func loadDMs2() {
        context.performAndWait {
            self.parseMessages(testDMs2())
        }
    }
    
    
    func loadMedia() {
        context.performAndWait {
            self.parseMessages(testMedia())
        }
    }
    
    func loadArticles() {
        context.performAndWait {
            self.parseMessages(testArticles())
        }
    }
    
    func loadFollows() {
        guard let account = account() else { L.og.debug("Preview.loadFollows - missing Account"); return }
        context.performAndWait {
            if let clNevent = PreviewFetcher.fetchEvents(account.publicKey, kind: 3, context: context).first?.toNEvent() {
                
                let pTags = clNevent.pTags()
                var existingAndCreatedContacts = [Contact]()
                for pTag in pTags {
                    let contact = Contact.fetchByPubkey(pTag, context: context)
                    guard contact == nil else {
                        // Skip if we already have a contact
                        existingAndCreatedContacts.append(contact!)
                        continue
                    }
                    // Else create a new one
                    let newContact = Contact(context: context)
                    newContact.pubkey = pTag
                    newContact.metadata_created_at = 0
                    newContact.updated_at = 0
                    existingAndCreatedContacts.append(newContact)
                }
                account.followingPubkeys.formUnion(Set(pTags))
            }
        }
    }
    
    func loadNewFollowersNotification() {
        guard let account = account() else { L.og.debug("Preview.loadNewFollowersNotification - missing Account"); return }
        context.performAndWait {
            let followers = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240,32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245,5195320c049ccff15766e070413bbec1c021bca03ee022838724a8ffb680bf3a,3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24,3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24,febbaba219357c6c64adfa2e01789f274aa60e90c289938bfc80dd91facb2899,aff9a9f017f32b2e8b60754a4102db9d9cf9ff2b967804b50e070780aa45c9a8".split(separator: ",").map { String($0) }
            let _ = PersistentNotification.create(pubkey: account.publicKey, followers: followers, context: context)
        }
    }
    
    
    func loadNewPostsNotification() {
        guard let account = account() else { L.og.debug("Preview.loadNewPostsNotification - missing Account"); return }
        context.performAndWait {
            let _ = PersistentNotification.createNewPostsNotification(pubkey: account.publicKey, context: context, contacts: [ContactInfo(name: "John", pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e")], since: 0)
        }
    }

    func loadZapsNotifications() {
        guard let account = account() else { L.og.debug("Preview.loadZapsNotifications - missing Account"); return }
        context.performAndWait {
            let content = "Zap failed for [post](nostur:e:78b8d514554a03dadd366e920768e439d3a45495ca3efa89010229aae823c07c) Something went wrong while paying invoice: not enough balance. Make sure you have at least 1% reserved for potential fees"
            let _ = PersistentNotification.createFailedNWCZap(pubkey: account.publicKey, message: content, context: context)
        }
    }
    
    // Needs account(s) and some kind = 1 events first
    func loadBookmarks() {
        context.performAndWait {
            let randomTextEventsR = Event.fetchRequest()
            randomTextEventsR.fetchLimit = 10
            randomTextEventsR.fetchOffset = Int.random(in: 0..<100)
            randomTextEventsR.predicate = NSPredicate(format: "kind == 1")
            let randomTextEvents = try? context.fetch(randomTextEventsR)
            if let randomTextEvents {
                for _ in 0..<10 {
                    if let random = randomTextEvents.randomElement() {
                        let bookmark = Bookmark(context: context)
                        bookmark.eventId = random.id
                        bookmark.createdAt = .now
                        bookmark.json = random.toNEvent().eventJson()
                    }
                }
            }
        }
    }
    
    // Needs account(s) and some kind = 1 events first
    func loadPrivateNotes() {
        context.performAndWait {
            let randomTextEventsR = Event.fetchRequest()
            randomTextEventsR.fetchLimit = 10
            randomTextEventsR.fetchOffset = Int.random(in: 0..<100)
            randomTextEventsR.predicate = NSPredicate(format: "kind == 1")
            let randomTextEvents = try? context.fetch(randomTextEventsR)
            if let randomTextEvents {
                for _ in 0..<10 {
                    let privateNote = CloudPrivateNote(context: context)
                    privateNote.content = ["Some more text here, I think I need to fix this in some way or another, I don't know how yet. But this text is a bit longer.","I made a private note here\nYo!","I made a private note here\nWith some more lines\n\nCool", "This is good"].randomElement()!
                    privateNote.eventId = randomTextEvents.randomElement()?.id
                    privateNote.type = CloudPrivateNote.PrivateNoteType.post.rawValue
                    privateNote.createdAt = Date.now
                    privateNote.updatedAt = Date.now
                }
            }
        }
    }
    
    func loadRelays() {
        context.performAndWait {
            let relay = CloudRelay(context: context)
            relay.url_ = "ws://localhost:3000/both"
            relay.createdAt = Date()
            relay.read = true
            relay.write = true
            
            let relay2 = CloudRelay(context: context)
            relay2.url_ = "ws://localhost:3001/both"
            relay2.createdAt = Date()
            relay2.read = true
            relay2.write = true
            
            let relay3 = CloudRelay(context: context)
            relay3.url_ = "ws://localhost:3008/write"
            relay3.createdAt = Date()
            relay3.read = false
            relay3.write = true
            
            let relay4 = CloudRelay(context: context)
            relay4.url_ = "ws://localhost:3008/read"
            relay4.createdAt = Date()
            relay4.read = true
            relay4.write = false
            
            let relay5 = CloudRelay(context: context)
            relay5.url_ = "ws://localhost:3008/other"
            relay5.createdAt = Date()
            relay5.read = true
            relay5.write = true
        }
    }
    
    func loadCloudFeeds(_ amount: Int = 10) {
        context.performAndWait {
            CloudFeed.generateExamples(amount: amount, context: context)
        }
    }
    
//    func loadRelayNosturLists() {
//        context.performAndWait {
//            NosturList.generateRelayExamples(context: context)
//        }
//    }
//    
    func loadRepliesAndReactions() {
        context.performAndWait {
            self.parseMessages(testRepliesAndReactions())
        }
    }
    
    func loadZaps() {
        context.performAndWait {
            self.parseMessages(testZaps())
        }
    }
    
    func loadNotifications() {
        context.performAndWait {
            self.parseMessages(testNotifications())
        }
    }
    
    func loadCommunities() {
        context.performAndWait {
            self.parseMessages(testCommunities())
        }
    }
    
    // Needs account, some kind = 1 events, and some contacts first
    func loadBlockedAndMuted() {
        context.performAndWait {
            let randomContactsR = Contact.fetchRequest()
            randomContactsR.fetchLimit = 10
            randomContactsR.fetchOffset = Int.random(in: 0..<100)
            let randomContacts = try? context.fetch(randomContactsR)
            if let randomContacts = randomContacts {
                for contact in randomContacts.randomSample(count: 3) {
                    CloudBlocked.addBlock(pubkey: contact.pubkey, fixedName: contact.anyName)
                }
            }
            
            let randomTextEventsR = Event.fetchRequest()
            randomTextEventsR.fetchLimit = 10
            randomTextEventsR.fetchOffset = Int.random(in: 0..<100)
            randomTextEventsR.predicate = NSPredicate(format: "kind == 1")
            let randomTextEvents = try? context.fetch(randomTextEventsR)
            if let randomTextEvents {
                for _ in 0..<10 {
                    if let random = randomTextEvents.randomElement() {
                        CloudBlocked.addBlock(eventId: random.id)
                    }
                }
            }
        }
    }
    
    func defaultSetup() {
        context.performAndWait {

            var messages:[String] = []
            messages.append(contentsOf: test1())
            
            messages.append(contentsOf: testMinimal())
            print("1 \(messages.count)")
            messages.append(contentsOf: testKind0Events())
            print("2 \(messages.count)")
            messages.append(contentsOf: testKind3Events())
            print("3 \(messages.count)")
            messages.append(contentsOf: testKind1Events())
            print("4 \(messages.count)")
//            messages.append(contentsOf: testKindMixedOldDunnoEvents())
            print("5 \(messages.count)")
            messages.append(contentsOf: testRepliesAndReactions())
            print("6 \(messages.count)")
//            messages.append(contentsOf: testSnowden())
            print("7 \(messages.count)")
//            messages.append(contentsOf: testBadges())
            print("8 \(messages.count)")
    //        messages.append(contentsOf: testMentions())
            print("9 \(messages.count)")
            messages.append(contentsOf: testKind6Events())
            print("10 \(messages.count)")
//            messages.append(contentsOf: testEfilter())
            print("11 \(messages.count)")
            messages.append(contentsOf: testZaps())
            print("12 \(messages.count)")
            messages.append(contentsOf: testSomeFakeAndRealZaps())
            print("13 \(messages.count)")
//            messages.append(contentsOf: testNotifications())
            print("15 \(messages.count)")
//            messages.append(contentsOf: testThread())
            print("16 \(messages.count)")
            messages.append(contentsOf: testDMs())
            print("17 \(messages.count)")
            messages.append(contentsOf: testTimelineThreads())
            print("19 \(messages.count)")
            messages.append(contentsOf: testHighlights())
            print("20 \(messages.count)")
            messages.append(contentsOf: testKind1063())
            print("21 \(messages.count)")
            
            print ("☢️☢️☢️ LOADED (SHOULD ONLY APPEAR ONCE) ☢️☢️☢️")
        }
    }

}

public typealias PreviewSetup = (_ pe:PreviewEnvironment) -> ()

struct PreviewContainer<Content: View>: View {
    @State private var pe = PreviewEnvironment.shared
    private var setup: PreviewSetup? = nil
    private let previewDevice: PreviewDevice
    private var content: () -> Content
    @State private var didSetup = false
    
    init(_ setup: PreviewSetup? = nil, previewDevice: PreviewDevice? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.setup = setup
        self.previewDevice = previewDevice ?? PreviewDevice(rawValue: PREVIEW_DEVICE)
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if didSetup, let la = NRState.shared.loggedInAccount {
                content()
                    .environment(\.managedObjectContext, pe.context)
                    .environmentObject(NRState.shared)
                    .environmentObject(la)
                    .environmentObject(pe.ss)
                    .environmentObject(pe.er)
                    .environmentObject(pe.ss)
                    .environmentObject(pe.sm)
                    .environmentObject(pe.dim)
                    .environmentObject(pe.themes)
                    .environmentObject(pe.dim)
                    .environmentObject(pe.npn)
                    .environmentObject(pe.cp)
                    .buttonStyle(NRButtonStyle(theme: pe.themes.theme))
                    .tint(pe.themes.theme.accent)
            }
            else {
                EmptyView()
            }
        }
        .onAppear {
            pe.themes.loadGreen()
            if pe.loadAccount() {
                if let setup {
                    setup(pe)
                }
            }
            didSetup = true
        }
        .previewDevice(previewDevice)
    }
}

struct PreviewFetcher {
    
    static let viewContext = DataProvider.shared().container.viewContext
    
    static func allContacts(context:NSManagedObjectContext? = nil) -> [Contact] {
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.sortDescriptors = []

        return try! (context ?? PreviewFetcher.viewContext).fetch(request)
    }
    
    static func fetchEvents(_ pubkey:String, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = Event.fetchRequest()
//        request.entity = Event.entity()
        if (kind != nil) {
            request.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind!)
        } else {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        return try! (context ?? PreviewFetcher.viewContext).fetch(request)
    }
    
    static func fetchEvents(_ pubkeys:Set<String>, kind:Int? = nil, context:NSManagedObjectContext? = nil) -> [Event] {
        let request = Event.fetchRequest()
        if let kind {
            request.predicate = NSPredicate(format: "pubkey IN %@ AND kind == %d", pubkeys, kind)
        } else {
            request.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request)) ?? []
    }
    
    static func fetchRelays(context:NSManagedObjectContext? = nil) -> [CloudRelay] {
        let request = CloudRelay.fetchRequest()
        request.predicate = NSPredicate(value: true)
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request)) ?? []
    }
    
    static func fetchAccount(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> CloudAccount? {
        let accountKey = pubkey ?? PREVIEW_ACCOUNT_ID
        let request = CloudAccount.fetchRequest()
        request.predicate = NSPredicate(format: "publicKey_ == %@", accountKey)
        request.sortDescriptors = []
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request))?.first
    }
    
    static func fetchEvent(_ id:String? = nil, context:NSManagedObjectContext? = nil) -> Event? {
        let request = Event.fetchRequest()
        if let id {
            request.predicate = NSPredicate(format: "id == %@", id)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request))?.randomElement()
    }
    
    static func fetchEvents(context: NSManagedObjectContext? = nil) -> [Event] {
        let request = Event.fetchRequest()
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request)) ?? []
    }
    
    static func fetchNRPost(_ id:String? = nil, context:NSManagedObjectContext? = nil, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false) -> NRPost? {
        if let event = fetchEvent(id) {
            if (withParents) {
                event.parentEvents = Event.getParentEvents(event)
            }
            return NRPost(event: event, withReplyTo: withReplyTo, withParents: withParents, withReplies: withReplies, plainText: plainText)
        }
        return nil
    }
    
    static func fetchNRPosts(context:NSManagedObjectContext? = nil, withReplyTo:Bool = false, withParents:Bool = false, withReplies:Bool = false, plainText:Bool = false) -> [NRPost] {
        fetchEvents().map { event in
            if (withParents) {
                event.parentEvents = Event.getParentEvents(event)
            }
            return NRPost(event: event, withReplyTo: withReplyTo, withParents: withParents, withReplies: withReplies, plainText: plainText)
        }
    }
    
    static func fetchContact(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> Contact? {
        let request = Contact.fetchRequest()
        if let pubkey {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
            request.fetchLimit = 1
        }
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request))?.randomElement()
    }
    
    static func fetchNRContact(_ pubkey:String? = nil, context:NSManagedObjectContext? = nil) -> NRContact? {
        let request = Contact.fetchRequest()
        if let pubkey {
            request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        }
        if let contact = (try? (context ?? PreviewFetcher.viewContext).fetch(request))?.randomElement() {
           return NRContact(contact: contact)
        }
        return nil
    }
    
    static func fetchList(context:NSManagedObjectContext? = nil) -> CloudFeed? {
        let request = CloudFeed.fetchRequest()
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request))?.randomElement()
    }
    
    static func fetchLists(context:NSManagedObjectContext? = nil) -> [CloudFeed] {
        let request = CloudFeed.fetchRequest()
        return (try? (context ?? PreviewFetcher.viewContext).fetch(request)) ?? []
    }
    
    
    static func fetchPersistentNotification(_ id:String? = nil, context:NSManagedObjectContext? = nil) -> PersistentNotification? {
        let request = PersistentNotification.fetchRequest()
        if let id {
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
            request.predicate = NSPredicate(format: "id == %@", id)
        } else {
            request.predicate = NSPredicate(value: true)
        }
        return try! (context ?? PreviewFetcher.viewContext).fetch(request).first
    }
}
