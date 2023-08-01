//
//  PostTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/08/2023.
//

import SwiftUI

struct HashTagInNameTest_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT","XX1",{"pubkey":"4ce6abbd68dab6e9fdf6e8e9912a8e12f9b539e078c634c55a9bff2994a514dd","content":"{\"banner\":\"https://nostr.build/i/p/nostr.build_24e245a3c325e0be16b6e32b2d93236b585c1d3dd657b8837ab04362a5af7d4f.gif\",\"damus_donation_v2\":100,\"website\":\"https://linktr.ee/manlikekweks\",\"nip05\":\"manlikekweks@nostrplebs.com\",\"picture\":\"https://nostr.build/i/nostr.build_c9bd06db3d60e1fa1badb65140b0b23cffc8c521bc844ecd258c4ba4a4ac8575.gif\",\"lud16\":\"powa@geyser.fund\",\"display_name\":\"Man Like Kweks ⚡️#PoWaKili23⚡️\",\"about\":\"WWJD / DCA2BTC \\n🇹🇿⚡️✊🏾\",\"name\":\"manlikekweks\"}","id":"2a9e740f6dc6ef9657bfc57c4f4bea1dab40b8caadca4de6bb6f1644bf29ff5a","created_at":1690884257,"sig":"5a7a79954580a7009371e27a01edb6c8c9bc1729f0ab3886aaa900e4c189bf22ed8901cd6d22817ff50fa63e47ba7d970b0f0cd5ce3efcd3a5c0808755a103ae","kind":0,"tags":[]}]"###,
                ###"["EVENT","XX2",{"pubkey":"693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb","content":"#[0] did you see the tag from post above? #bitcoin I feel that when I post from the community the tagging is wonky. ","id":"60cae008116dccccdf970e36a8e7e789c2fc10e950cae9eefe1069235bc34faf","created_at":1690881254,"sig":"354a910fab64a640f52c9f900a4897b3925a82471d5f0940b8f635549fe44fe627855b28bf1f93224ad425ecb5619a54f582a7c6655e1bdc5231b8fb27f8eeb6","kind":1,"tags":[["p","4ce6abbd68dab6e9fdf6e8e9912a8e12f9b539e078c634c55a9bff2994a514dd"],["e","03d933fd31532369184eb307780de3a4b74eefd708a4225f13e0c897fcbd859f","","root"],["p","693c2832de939b4af8ccd842b17f05df2edd551e59989d3c4ef9a44957b2f1fb"]]}]"###
            ])
        }) {
            if let post = PreviewFetcher.fetchNRPost("60cae008116dccccdf970e36a8e7e789c2fc10e950cae9eefe1069235bc34faf") {
                NoteRow(nrPost: post) 
            }
        }
    }
}
