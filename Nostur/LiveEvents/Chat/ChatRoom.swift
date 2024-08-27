//
//  ChatRoom.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI

struct ChatRoom: View {
    
    public let aTag: String
    public let theme: Theme
    public let anonymous: Bool
    
    @StateObject private var vm = ChatRoomViewModel()
    @Namespace private var bottom
    @State private var message: String = ""
    @State private var account: CloudAccount? = nil
    @State private var timer: Timer?
    
    var body: some View {
        ScrollViewReader { proxy in
            if let account {
                AvailableWidthContainer {
                    VStack(spacing: 0) {
                        List {
                            switch vm.state {
                            case .initializing:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(theme.background)
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                                    .onAppear {
                                        try? vm.start(aTag: aTag)
                                    }
                            case .loading:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(theme.background)
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .ready:
                                if vm.messages.isEmpty {
                                    VStack {
                                        Spacer()
                                        Text("Welcome to the chat")
                                    }
                                        .scaleEffect(x: 1, y: -1, anchor: .center)
                                        .centered()
                                        .listRowInsets(.init())
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(theme.background)
                                }
                                else {
                                    ForEach(vm.messages) { nrChat in
                                        ChatRow(nrChat: nrChat)
                                            .padding(.vertical, 5)
                                        .scaleEffect(x: 1, y: -1, anchor: .center)
                                    }
                                    .listRowInsets(.init())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(theme.background)
                                }
                            case .timeout:
                                VStack {
                                    Text("timeout")
                                }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(theme.background)
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .error(let string):
                                Text(string)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(theme.background)
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            }
                        }
                        .scrollContentBackgroundCompat(.hidden)
                        .listStyle(.plain)
                        .safeAreaScroll()
                        .scaleEffect(x: 1, y: -1, anchor: .center)
                        .onChange(of: vm.state) { newValue in
                            if newValue == .ready {
                                proxy.scrollTo(bottom)
                            }
                        }
                        
                        if !anonymous {
                            HStack {
                                MiniPFP(pictureUrl: account.pictureUrl, size: 40.0)
                                ChatInputField(message: $message, startWithFocus: false, onSubmit: submitMessage)
                            }
                            .padding(.bottom, 15)
                        }
                    }
                }
            }
        }
        .onAppear {
            account = Nostur.account()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        
        
    }
    
    private func submitMessage() {
        // Create and send DM (via unpublisher?)
        guard let account = self.account, account.privateKey != nil else { NRState.shared.readOnlyAccountSheetShown = true; return }
        var nEvent = NEvent(content: message)
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        nEvent.kind = .chatMessage
        nEvent.tags.append(NostrTag(["a", aTag]))
        
        nEvent.publicKey = account.publicKey
        
        if account.isNC {
            nEvent = nEvent.withId()
            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                Unpublisher.shared.publishNow(signedEvent, skipDB: true)
                sendNotification(.receivedMessage, RelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
                bg().perform {
                    Importer.shared.existingIds[signedEvent.id] = EventState(status: .RECEIVED, relays: "self")
                }
            })
            
            message = ""
        }
        else {
            guard let signedEvent = try? account.signEvent(nEvent) else { return }
            Unpublisher.shared.publishNow(signedEvent, skipDB: true)
            sendNotification(.receivedMessage, RelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
            bg().perform {
                Importer.shared.existingIds[signedEvent.id] = EventState(status: .RECEIVED, relays: "self")
            }
            message = ""
        }
    }
    
    private func startTimer() { // Make sure real time sub for chat messages stays active
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            vm.updateLiveSubscription()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","profile",{"sig":"05d6005b8b94614e914cac88f42f6f8cb0e28d7ba87d3dba70b722d96d138344a31b4cc00452aa19f9bba5bc6efd992acbcea108c58f7793a68bb1e26207d170","kind":0,"id":"dac0c3514ebabf2461da6ef43e9394cf8ebe2df3d4c87f15e6b9d99e92b3241c","created_at":1720383483,"pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","content":"{\"picture\":\"https://void.cat/d/AYx2c8e34mRFtaZpDA7yKK.webp\",\"banner\":\"https://image.nostr.build/94318f86f4ed7942bce694761d5d3f59a3756a843dc30adb5a4860262982d3a9.jpg\",\"name\":\"SimplySarah\",\"display_name\":\"SimplySarah\",\"about\":\"Music, Food, Art, Travel 🎶🍴🎨✈️\",\"nip05\":\"simplysarah@iris.to\",\"lud16\":\"simplysarah@getalby.com\",\"created_at\":1718236977,\"displayName\":\"SimplySarah\",\"pubkey\":\"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948\",\"npub\":\"npub1n0pdxnwa4q7eg2slm5m2wjrln2hvwsxmyn48juedjr3c85va99yqc5pfp6\",\"website\":\"https://simplysarah.npub.pro\"}","tags":[["alt","User profile for SimplySarah"]]}]"###,
            ###"["EVENT","profile",{"created_at":1721330168,"pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","kind":0,"sig":"04a4dc0aade8e5da470bea993112641445ddbc0c75a85eee144fe50d234c08160c62344ccc5fc79ea19ab51b9a50bd13e71429d0a3115f8e6e8da9798050f056","id":"dad359646ae21e8e2cde981101a561978af374398fce7a6abd43e5cce73d7bd2","tags":[],"content":"{\"lud06\":\"\",\"nip05\":\"QW@NostrPlebs.com\",\"name\":\"QW\",\"website\":\"https:\\/\\/fountain.fm\\/show\\/0N6GGdZuYNNG7ysagCg9\",\"lud16\":\"qw@primal.net\",\"display_name\":\"𝕼𝖚𝖎𝖊𝖙 𝖂𝖆𝖗𝖗𝖎𝖔𝖗\",\"banner\":\"https:\\/\\/m.primal.net\\/JNSN.jpg\",\"about\":\"Co-Host Plebchain Radio \\nBuilding Nostr PHX\\nV4V Advocate\\n#Plebchain  #Zapathon #Plebdad\\n\",\"picture\":\"https:\\/\\/image.nostr.build\\/a501f0c280e380a597232268a01dcd46fb5e03deab7c9ff05d44e480784cf945.gif\"}"}]"###,
        ])
        pe.loadContacts()
//        pe.parseNoDbMessages([
//            ###"["EVENT","nest",{"created_at":1721418385,"kind":30311,"sig":"24ff716cdbca267ec0019362b28f1cecc818516d9f507ad58fb6beefa6dea9bb3efc82325daea1be6cce4b5cd67def61b1e2d7306b02c027782653e64672160c","id":"2b23be2eb8507bd651c84d9313eef09ca3ec245db29a6dd24432adfe31fa0703","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","tags":[["color","gradient-1"],["d","f65e7db0-8072-4073-9280-ecf15ae9fd52"],["image","https://image.nostr.build/3ecd80a26bec11a7ea4a9a23d485040209652eae1b165fd4fb722a6e6279f409.jpg"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://nostr.land"],["service","https://nostrnests.com"],["starts","1721418385"],["status","live"],["streaming","wss+livekit://nostrnests.com:443"],["streaming","https://nostrnests.com/api/v1/live/f65e7db0-8072-4073-9280-ecf15ae9fd52/live.m3u8"],["summary","Guest : Ben Weeks"],["title","PCR70"]],"content":""}]"###,
//            
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"0a882abbb5f6facfdacce9438bc2c2b3aa78bcc3e312e1c7a0b6b84e8d96d010","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","created_at":1721422196,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"Ahhhh Summer camp is presented by Tuttle Twins! Love it","sig":"53178cd6c6b1595c8c5f052dc27dcc96e0a7c48f37cf58d30bd6a7fd080ad3f4e9e98f213680e5e9b94ed13daa56a9e40a196fd3064fff83ce252a02491e1ffe"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"ed1593fd71b5e369dcbcf050c966cee0776012ba9a5c95df4b687eabaaaa8b5f","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","created_at":1721422164,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"lightningpiggy.com that is","sig":"f014c2e02bc524f630dd9e7de70239ba5c88a43eb3e2485ba798283878409757feb789a9704536f03d17667fd39a6848f6983ac3d4acc32c1f816fee7935c634"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"d40c293ec81687702ff8d73210d9c13ca069b0300f93b3fe40792ef929a045b6","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","created_at":1721422134,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"So much artwork and imaginantion built by children. ","sig":"d6061621fdd88f619f8577d8385267f52ecf547929cccd623e76a80818980916ab147382cdeb48a43c57b7dd04aba682ea45c9256e2904e97d660a05f3beb565"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"a1de2f782bac78a8792ffc8cd05b54f4e7d2a574fcfb4cbca2d04557e629d147","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","created_at":1721422109,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"I love this website","sig":"718d0814995592efbe47d95577688ac121226bb0d087fee7e64c844f76d3029616c647f7c53c118df6dec6cf68bd75b65c249980dc21cafe9b89d27a9d436614"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"70fe8615ca25d9a9300f0816360c14b2ad53339a5ce0d519924a2543899d8564","pubkey":"971615b70ad9ec896f8d5ba0f2d01652f1dfe5f9ced81ac9469ca7facefad68b","created_at":1721422028,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"Lightning Piggy will be at the Bitcoin 2024 Satoshi Summer Camp in Nashville next week (Friday). I think they still have a few places for kids. https://bitcoin2024.b.tc/2024/summer-camp","sig":"d0991f62d8c0271f16643227bddff5ff6998d23e2a9be4f99139889e191bf8316e504ed891bbb19eeec6d54abd6a915082bff2e8f0e6cd520b4f52272c9f2a76"}]"###,
//            ###"["EVENT","DB-CHAT-1",{"kind":1311,"id":"286c918c4729ba886fdb817bb3fcc9fb4bae52c46fa3746cf53947eefae56d4c","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721422006,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"this is cute hour","sig":"16be048fc2d9e3cfd43b1c2779585a153fbc7aed10716db7becc75eb2788ad54df6aaa93c4c8acdc8a7a9606eed6c8037a1007291cb25957c93a01b500b00b37"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"07ede100b2c372d12e0ac7c6810312de3863d9c5f86c5df359a8096cab1d4116","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721421996,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"awww satoshi summer camp","sig":"0b42bbca4585c6f183d5da9cd79fb6b9056fee09c86f3ec1a520f12a1ff1c9e4aece368037abe831700fdda8c544610c56b65aec19f41a33e3179516b31c332a"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"c271996948c7287857ac65f14f2849c5d2bc952f894f97010142020b837514d2","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721421968,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"split payments for kids, sooo adorable","sig":"446198f7d96e3c7987414c76cbd25993372232ef34e2738d71fbc5e6bf6e1bcca3ac8192394ca52c0c01f9986b34c59cb3e10708645bff2bb32d9b474e63cfcb"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"229cfaa487b4c558d40bbcefb46a0b55666df570074af0fea3c2393f37bdbde3","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721421366,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"lightningpiggy.com ","sig":"208c3f2e2b64cb7ebea8956d9b5834b813f60ca6a4314dab752aad3eb13ddd655343004e4d176142afe6b31c9d0bccc866ee667368b97ffb930dbf0fc31cca08"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"0a31cc89e5cf5fddfde2acee0764ffe670009216506f1f34bbcd6804badee415","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721421349,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"lightning piggy is a cute idea","sig":"694336b0c953254caa6657388e3d3c3f537136d173d1d6e9eb079502a0bc91fb54239c85e4fc952986c3cdb0cf663e1fd043cf734d59ed309d63643064f00f32"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"916a6428245cd2d333a4855c981a157a0295954fbf74b97332313ca1187cfb25","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721421082,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"all or nothing!","sig":"87e821352c3f5de73a92ee77b45c14ffd02b5722efef528d607d7f96cdb343c21ea0f890e5e37b973988b36d36b165b24a6da3dbf44269cbf685b672b0618483"}]"###,
//            
//            
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"3f63128b671d72b78d1d1a9e5af2a1d97b70390f98c6a9880c23fdf62229175e","pubkey":"5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e","created_at":1721420168,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"Lets chat it up!","sig":"15a06aa7d54a872e78c1885055547f6b70511f6c873d5ff3737c4c9ac9a7c79127c88e2d1db4d39f921f9fa5e60825a8801222cbab8636cfef8dc7075197446e"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"26474385583cc0ff654e9d11a0cc2f7f598e83d436f1c21dc50ff44561cc25e8","pubkey":"9bc2d34ddda83d942a1fdd36a7487f9aaec740db24ea79732d90e383d19d2948","created_at":1721419360,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"Yo","sig":"e767d1f670190c9571f23775c7ef3b8fd9031787ba6ab79b24ed8ed579a3fe63363b777e4966d20198097ed5f1c753fb229ba265f267f32bdbc4862d5da33107"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"ee372dde608acf138e3ce3f1bcd6bc474c9252e15cfa25870ec7d6e8d46af64a","pubkey":"971615b70ad9ec896f8d5ba0f2d01652f1dfe5f9ced81ac9469ca7facefad68b","created_at":1721419274,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://nos.lol/"]],"content":"Yo :-)","sig":"36e49b80fe8eb78f9e6f63a12a8d4db95cf86d23879d002a0948b0da1f7d231751cd2297e5d55c9d7eb2489c2775317ad326ed533bc6f6f45d920e72d858026e"}]"###,
//            ###"["EVENT","-DB-CHAT-1",{"kind":1311,"id":"d59d394e7129c3e18e1ec353a78baced2d57568faf0a061af197fb2207673298","pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","created_at":1721419266,"tags":[["a","30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52","wss://relay.damus.io/"]],"content":"Yo","sig":"e4fd9d8424f2f6922ed3777f882b65ef5db4abe3fd030e12292232035b1a75c22654c52e594845b46e1ff06c2646f8fdff64de9463bbb8ec2cb536fa9fd62a27"}]"###
//        ])
    }){
        Box {
            ChatRoom(aTag: "30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52", theme: Themes.default.theme, anonymous: false)
        }
    }
}
#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","e",{"kind":30311,"id":"75558b5933f0b7002df3dbe5356df2ab1144f8c0595e8d60282382a2007d5ed7","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1721669595,"tags":[["d","82d27633-1dd1-4b38-8f9d-f6ab9b31fc83"],["title","Fiatjaf \u0026 utxo play dominion"],["summary","Come watch this very exciting game"],["image","https://dvr.zap.stream/zap-stream-dvr/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33278578238\u0026Signature=X4Jo1oAm5pIg0YZ40CobUUdpD2A%3D"],["status","ended"],["p","e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1721664799"],["service","https://api.zap.stream/api/nostr"],["recording","https://data.zap.stream/recording/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83.m3u8"],["ends","1721669595"]],"content":"","sig":"3f03a0de44dd2eec8dd045d5dd2242d1558f2af7719955e9ceb300c4ee14f26e4a170b13db923fb313bf4fd5d2c60be344f7901ea3ef5dd7f0fcb8df908b8b21"}]"###,
            ###"["EVENT","moizen",{"kind":0,"id":"846806929813bdd05b4d9c9ecac10193106530c61e5c1f396162df3d69f2e8db","pubkey":"dbc828cc8b33efa73a60ce27bfcf6e039fd602af289f7deb717d766aed78a663","created_at":1718928825,"tags":[],"content":"{\"name\":\"moizen\",\"picture\":\"https://image.nostr.build/f3a2b54e3e335993cc4baf20e88e03b6006110955f6d97fb3f70dbec221e7765.jpg\",\"display_name\":\"⛩oizen\",\"about\":\"architect | pleb\\nplants, stones and pepes catalogs\",\"website\":\"https://moizen.xyz\",\"lud16\":\"moizen@getalby.com\",\"banner\":null,\"nip05\":\"moizen@moizen.xyz\",\"pubkey\":\"dbc828cc8b33efa73a60ce27bfcf6e039fd602af289f7deb717d766aed78a663\",\"displayName\":\"⛩oizen\"}","sig":"6a1f709a02987d9ce610af19c4283e856b975edd2078ff68f7f664a18928659157f266f77463c2a4da43635c41b2e1435134da50a95447e3b66d6a2093cc10a0"}]"###,
            ###"["EVENT","utxo",{"kind":0,"id":"885d11734015eb69c0ebbdef7d240780206c115049f8afac5a6321517a71c4e3","pubkey":"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","created_at":1721395552,"tags":[["alt","User profile for utxo"]],"content":"{\"name\":\"utxo\",\"about\":\"we are so back\",\"display_name\":\"utxo\",\"picture\":\"https://i.nostr.build/6G6wW.gif\",\"lud16\":\"utxo1@getalby.com\",\"nip05\":\"utxo.one\",\"website\":\"bitvora.com\",\"banner\":\"https://i.nostr.build/RdZq.gif\"}","sig":"1b6abe57ffe0f1ac943e233577784cf45af836d0214f69af875b6a4a7a1ceffa8ca6c318a9bc5056399a442486de3a90f1680a4d7679712ff434ab2154327adb"}]"###,
            ###"["EVENT","gary",{"kind":0,"id":"90537f59169ff6046e47c89633f81079d5e28cfd18ba3bec1870ca1f23c41412","pubkey":"d3d74124ddfb5bdc61b8f18d17c3335bbb4f8c71182a35ee27314a49a4eb7b1d","created_at":1720693551,"tags":[["alt","User profile for average_gary"]],"content":"{\"name\":\"average_gary\",\"about\":\"Chief Cryptologic Technician (Interpretive)\\n\\nBe peaceful, not harmless.\\n \\nhttps://virginiafreedom.tech\\n\\nhttps://shenandoahbitcoin.club\\n\\nhttps://bitcoinveterans.org\",\"picture\":\"https://i.nostr.build/EnQZl.gif\",\"nip05\":\"gary@ShenandoahBitcoin.Club\",\"banner\":\"https://i.nostr.build/lLRMv.jpg\",\"display_name\":\"average_gary\",\"lud16\":\"gary@minibits.cash\",\"website\":\"https://garykrause.dev\"}","sig":"5f04d1e156ab393ea1fc91ef28a7ed3d745184dbff1cc82c04c7c59855380382994e721e41aa0b6e0e80561ba473bc160e423078d23eb7c97c7902747566183e"}]"###, ###"["EVENT","gazoo",{"kind":0,"id":"ae8a162c06df3de4ee4375ca63ad761386e49c5e2da263ac397a15c8043a9583","pubkey":"f6adc1cad551b73f0391eaf7cf2b359690da9ad7d0cb0b77d2bed8c89fece65f","created_at":1713393504,"tags":[],"content":"{\"display_name\":\"The Great Gazoo\",\"about\":\"Spinning records sometimes\",\"picture\":\"https://cdn.nostr.build/i/2f1e31ec624c3d376de1eafe75652b9477017abd4bfe71e947751eaa543c31a0.jpg\",\"name\":\"The great gazoo\",\"lud06\":\"\",\"banner\":\"https://void.cat/d/DpM8y2zhNjG3NghPyHrqct.webp\",\"lud16\":\"greatgazoo@getalby.com\",\"website\":\"\",\"nip05\":\"thegreatgazoo@snort.social\"}","sig":"ac65ac1489fb28540ff2cfaa15890707e021dcddb7f73618a76db7d72c9de0da4df6f3444d1c885e32a62569f1560c8adf390cf1c16f98d02c3ba14c84f83aed"}]"###,
        ])
//        pe.loadContacts()
        pe.loadChats()
    }){
        Box {
            ChatRoom(aTag: "30311:cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5:82d27633-1dd1-4b38-8f9d-f6ab9b31fc83", theme: Themes.default.theme, anonymous: false)
                .padding(10)
        }
    }
}


struct ChatRow: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject public var nrChat: NRChatMessage
    @State private var didStart = false
    
    var body: some View {
        switch nrChat.nEvent.kind {
        case .zapNote:
            if let zapFromAttributes = nrChat.zapFromAttributes {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        MiniPFP(pictureUrl: zapFromAttributes.contact?.pictureUrl)
                            .onTapGesture {
                                if let nrContact = zapFromAttributes.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: zapFromAttributes.pubkey))
                                }
                            }
                        Text(zapFromAttributes.anyName ?? "...")
                            .foregroundColor(themes.theme.accent)
                            .onTapGesture {
                                if let nrContact = zapFromAttributes.contact {
                                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                                }
                                else {
                                    navigateTo(ContactPath(key: zapFromAttributes.pubkey))
                                }
                            }
                        Ago(zapFromAttributes.created_at).foregroundColor(themes.theme.secondary)
                    }
                    ChatRenderer(nrChat: nrChat, availableWidth: dim.listWidth, forceAutoload: false, theme: themes.theme, didStart: $didStart)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: 450, alignment: .top)
                    
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MiniPFP(pictureUrl: nrChat.contact?.pictureUrl)
                        .onTapGesture {
                            if let nrContact = nrChat.contact {
                                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                            }
                            else {
                                navigateTo(ContactPath(key: nrChat.pubkey))
                            }
                        }
                    Text(nrChat.anyName ?? "...")
                        .foregroundColor(themes.theme.accent)
                        .onTapGesture {
                            if let nrContact = nrChat.contact {
                                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                            }
                            else {
                                navigateTo(ContactPath(key: nrChat.pubkey))
                            }
                        }
                    Ago(nrChat.created_at).foregroundColor(themes.theme.secondary)
                }
                ChatRenderer(nrChat: nrChat, availableWidth: dim.listWidth, forceAutoload: false, theme: themes.theme, didStart: $didStart)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 450, alignment: .top)
                
            }
        }
    }
}
