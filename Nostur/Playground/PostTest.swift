//
//  PostTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/08/2023.
//

import SwiftUI

struct PostTest_Previews: PreviewProvider {
    
    
    static func loadParents (_ event:Event) -> Event {
        let withP = event
        withP.parentEvents = Event.getParentEvents(event, fixRelations: true)
        return withP
    }
    
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT", "bug", {"kind":1,"sig":"11858cacfa18147eb04c2e283775140cf1fc204f17b963ed40f75e6e54831467d5dcb646766c42873a3d5b2741339be0471fc87598057e68484620f2b78f7d3c","id":"0e090529d5fa674eeb07a3a17a012349ee6c1db56fa172fd3dc0f704f46a8e3e","tags":[],"pubkey":"f0019b0732a2b1a70360fb8f5ddb7f40544f8b46b0c928e300b519f6d53ec7c9","created_at":1737317165,"content":"ムカつくから死ねないけど、座りすぎは健康に悪いって話だよ。そこにJoin Nostrリンクがあるよ！滝は82メートルもあって、TikTokを運営する新たな合弁事業を設け、アメリカが合弁事業の50％の株式を持つことを明らかにしてれば勝手に育つと思ったら、本当にのど飴を取り出したんだろうが。"}]"###,
                ###"["EVENT","A",{"pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","content":"My motivation this morning was that Ralf is a good, kind hearted, and giving person.","id":"597392f3a86123bd94fbf686a46c4bf0743822cfa8c19d96b9c60fe0fbd63719","created_at":1692806103,"sig":"2d90728c4125973149381004e1310a13fcea9ee437b51a71297d29c78f34d4b25fd902a4c879ac935d71c83b0423526c56e3d0e1e15e6f906cb477fdfb87c5fc","kind":1,"tags":[["e","c31633ed62c9bf075c2779ebebce945a8f24f1963909f43b17fb2fcd90541c4a","","root"],["e","a3ee198c9240ed9d01c03fbc1149829bb575b13434087486a4447efeffab5082","","reply"],["p","5be6446aa8a31c11b3b453bf8dafc9b346ff328d1fa11a0fa02a1e6461f6a9b1"],["p","d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a"]]}]"###,
                ###"["EVENT","B", {"pubkey":"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245","content":"Yup same, saying we have ill intentions when we had a legitimate concern","id":"84bfeabb613520f9d2951c8d137c603dc91acaec0c7124e49093d361a5fc3061","created_at":1692806182,"sig":"97a7c3e8828dab860d8074b2b2974c894d255149feb57876f21c79597c92c5bc647058b0df250369d484bd56cb5d0f74239a358c9b6b3ee82682cdc288068437","kind":1,"tags":[["e","c31633ed62c9bf075c2779ebebce945a8f24f1963909f43b17fb2fcd90541c4a"],["e","597392f3a86123bd94fbf686a46c4bf0743822cfa8c19d96b9c60fe0fbd63719"],["p","5be6446aa8a31c11b3b453bf8dafc9b346ff328d1fa11a0fa02a1e6461f6a9b1"],["p","d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"]]}]"###,
                ###"["EVENT","XX1",{"pubkey":"4ce6abbd68dab6e9fdf6e8e9912a8e12f9b539e078c634c55a9bff2994a514dd","content":"{\"banner\":\"https://nostr.build/i/p/nostr.build_24e245a3c325e0be16b6e32b2d93236b585c1d3dd657b8837ab04362a5af7d4f.gif\",\"damus_donation_v2\":100,\"website\":\"https://linktr.ee/manlikekweks\",\"nip05\":\"manlikekweks@nostrplebs.com\",\"picture\":\"https://nostr.build/i/nostr.build_c9bd06db3d60e1fa1badb65140b0b23cffc8c521bc844ecd258c4ba4a4ac8575.gif\",\"lud16\":\"powa@geyser.fund\",\"display_name\":\"Man Like Kweks ⚡️#PoWaKili23⚡️\",\"about\":\"WWJD / DCA2BTC \\n🇹🇿⚡️✊🏾\",\"name\":\"manlikekweks\"}","id":"2a9e740f6dc6ef9657bfc57c4f4bea1dab40b8caadca4de6bb6f1644bf29ff5a","created_at":1690884257,"sig":"5a7a79954580a7009371e27a01edb6c8c9bc1729f0ab3886aaa900e4c189bf22ed8901cd6d22817ff50fa63e47ba7d970b0f0cd5ce3efcd3a5c0808755a103ae","kind":0,"tags":[]}]"###,
                ###"["EVENT","XX2",{"pubkey":"693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb","content":"#[0] did you see the tag from post above? #bitcoin I feel that when I post from the community the tagging is wonky. ","id":"60cae008116dccccdf970e36a8e7e789c2fc10e950cae9eefe1069235bc34faf","created_at":1690881254,"sig":"354a910fab64a640f52c9f900a4897b3925a82471d5f0940b8f635549fe44fe627855b28bf1f93224ad425ecb5619a54f582a7c6655e1bdc5231b8fb27f8eeb6","kind":1,"tags":[["p","4ce6abbd68dab6e9fdf6e8e9912a8e12f9b539e078c634c55a9bff2994a514dd"],["e","03d933fd31532369184eb307780de3a4b74eefd708a4225f13e0c897fcbd859f","","root"],["p","693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb"]]}]"###,
                ###"["EVENT", "XX3", {"pubkey":"693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb","content":"#nostrcypher #V\n\nhttps://cdn.stemstr.app/stream/f65eb219ce16034f408b0105f857094d2b157dc9f252fafbde9334d7afc2318a.m3u8\n\nSOVEREIGN - @npub1l2h50te8u00qd6plx3hudn82p24lcafqmqhlayxy3h7dwsxxnj4q28n2lz x @npub1xv6axulxcx6mce5mfvfzpsy89r4gee3zuknulm45cqqpmyw7680q5pxea6 x @npub1dy7zsvk7jwd547xvmpptzlc9muhd64g7txvf60zwlxjyj4aj78as6hljz5 x @npub1ehg5cqekjlj2jqqhc7z9y2sjq4am42dntahcyn225twv9xdu2m2sl5qe5t x @npub1qfc7rwddjl3lzhkhgge8ch82xjfm6e3gqcgk8zm6pahz3tvvl7gq88xnrh x @npub1fnn2h0tgm2mwnl0kar5ez25wztum2w0q0rrrf326n0ljn999znwsqf4xnx x @npub1039vu6k9v0q5p2ut6z6f78d5mws7xa0knjkfdvqyy45m6uyxht5qt2j08e x @npub1xr8tvnnnr9aqt9vv30vj4vreeq2mk38mlwe7khvhvmzjqlcghh6sr85uum\n\nIf you feel like zapping, remember we don’t have sap splits yet. 😉\n\nhttps://cdn.satellite.earth/3a78579b9b588184a418f99fd1377f0da5db462b7036566fef80e3e8addcdad1.jpg","id":"03d933fd31532369184eb307780de3a4b74eefd708a4225f13e0c897fcbd859f","created_at":1690851437,"sig":"aab7ce7eebaecc4f9ffecfb6dd41d3f26c46b40f8f4932f815763a2f77efa7a4c029c767d3fe4978f7cd89732a617ccfa0c6947a193aafd0d4484ec42ebac913","kind":1,"tags":[["a","34550:693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb:NostrCypher"],["r","https://cdn.stemstr.app/stream/f65eb219ce16034f408b0105f857094d2b157dc9f252fafbde9334d7afc2318a.m3u8"],["subject","#nostrcypher #V"]]}]"###,
                #####"["EVENT","XX4",{"pubkey":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","content":"### #Amethyst v0.72.0-APLHA: New Memory Management\n\nThis new version constantly prunes the memory used by downloaded events by deleting them from memory after use. This leads to re-downloading some replies, zaps, and reactions when the user brings an event back into view. The re-downloading will be removed once we finish our local database implementation. \n\n- Adds aggressive memory management to avoid Out of Memory\n- Fixes the Back button leaving the app issue\n- Interns event strings to avoid duplicating memory with hashes and pubkeys\n- Improves search by looking into all tags of all events\n- Improves Tamil Translations by @velram \n- Adds missing translations cs/de/se by nostr:npub1e2yuky03caw4ke3zy68lg0fz3r4gkt94hx4fjmlelacyljgyk79svn3eef\n- Adds cryptographic and base event support for NIP-24 (GiftWraps and Sealed Gossip)\n- Increases confidence requirements for the Translator\n- Refactors the event creation into a Factory\n- Adds new kinds to the hashtag and geotag search feeds\n- Fixes the explainer text of the geohash addon\n- Updates to the latest libraries\n- Removes Leakcanary for debug builds\n- Cleans up unused values in strings\n- Fix: Ignores past version of addressable content in feeds\n- Fix: Avoids showing community definition types in the community feed.\n- Fix: Avoids downloading 1000s of Nostr Connect events that some clients are generating. \n\nDownload:\n- [Play Edition](https://github.com/vitorpamplona/amethyst/releases/download/v0.72.0/amethyst-googleplay-universal-v0.72.0.apk)\n- [F-Droid Edition](https://github.com/vitorpamplona/amethyst/releases/download/v0.72.0/amethyst-fdroid-universal-v0.72.0.apk)","id":"dcfbf61fb232e0e916fc28945a588febcdba4f523ce42959f7f2177364d91b37","created_at":1690905822,"sig":"066d53f80aef5475e22c319142b08df1f096848488cea4910d16f07881d731a3fc60a46b36099ea706c0dd969a16c737d7d6be5e0c39471dc9857049f5445249","kind":1,"tags":[["p","ca89cb11f1c75d5b6622268ff43d2288ea8b2cb5b9aa996ff9ff704fc904b78b"],["t","amethyst"]]}]"#####
            ])
        }) {
            PreviewFeed {
                if let post = PreviewFetcher.fetchNRPost("0e090529d5fa674eeb07a3a17a012349ee6c1db56fa172fd3dc0f704f46a8e3e") {
                    PostOrThread(nrPost: post)
                }
                
                if let event = PreviewFetcher.fetchEvent("84bfeabb613520f9d2951c8d137c603dc91acaec0c7124e49093d361a5fc3061") {
                    PostOrThread(nrPost: NRPost(event: Self.loadParents(event), withReplyTo: true, withParents: true))
                }
//                if let post = PreviewFetcher.fetchNRPost("dcfbf61fb232e0e916fc28945a588febcdba4f523ce42959f7f2177364d91b37") {
//                    PostOrThread(nrPost: post)
//                }
                if let post = PreviewFetcher.fetchNRPost("03d933fd31532369184eb307780de3a4b74eefd708a4225f13e0c897fcbd859f") {
                    PostOrThread(nrPost: post)
                }
//
                if let post = PreviewFetcher.fetchNRPost("60cae008116dccccdf970e36a8e7e789c2fc10e950cae9eefe1069235bc34faf") {
                    PostOrThread(nrPost: post)
                }
            }
        }
    }
}

struct PreviewFeed<Content: View>: View {
    
    @Environment(\.theme) private var theme
    let content: Content
    
    init(@ViewBuilder _ content: ()->Content) {
        self.content = content()
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        AvailableWidthContainer {
            ScrollViewReader { proxy in
                List {
                    content
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .scrollContentBackgroundHidden()
            }
            .overlay(alignment: .center) {
                OverlayPlayer()
            }
        }
    }
}
