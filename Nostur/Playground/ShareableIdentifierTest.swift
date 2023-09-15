//
//  ShareableIdentifierTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI

struct ShareableIdentifierTest: View {
    
    var s:ShareableIdentifier?
    var ss:ShareableIdentifier?
    var sss:ShareableIdentifier?
    var error:String = ""
    var lnurl:String?
    
    init() {
        do {
            sss = try ShareableIdentifier("naddr1qqxnzd3cxyerxd3h8qerwwfcqgsgydql3q4ka27d9wnlrmus4tvkrnc8ftc4h8h5fgyln54gl0a7dgsrqsqqqa28qy28wumn8ghj7un9d3shjtnyv9kh2uewd9hszrthwden5te0dehhxtnvdakqvtl0f3")
            
            ss = try ShareableIdentifier("nprofile1qqsrjerj9rhamu30sjnuudk3zxeh3njl852mssqng7z4up9jfj8yupqpzamhxue69uhhyetvv9ujumn0wd68ytnfdenx7tcpz4mhxue69uhkummnw3ezummcw3ezuer9wchszxmhwden5te0dehhxarj9ekkj6m9v35kcem9wghxxmmd9uq3xamnwvaz7tm0venxx6rpd9hzuur4vghsz8nhwden5te0dehhxarj94c82c3wwajkcmr0wfjx2u3wdejhgtcsfx2xk")

            s = try ShareableIdentifier("nevent1qqsfgf8u2nx94dqh7sja4mzyy7ve00dwkhja8u6pcecca6t300alphgprdmhxue69uhhyetvv9ujummjv9hxwetsd9kxctnyv4mz7q3qr0rs5q2gk0e3dk3nlc7gnu378ec6cnlenqp8a3cjhyzu6f8k5sgsxpqqqqqqzm9c2j8")
            
//            lnurl = try Bech32.decode(lnurl: "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHHW6TWDE5KUEMZD3HHWEM4DCURVNYWCP4").absoluteString
        }
        catch {
            print(error)
            self.error = error.localizedDescription
        }
    }
    
    var body: some View {
        if let s = sss {
//            Text("\(Event.entity().name ?? "test")")
//            Text(s.bech32string)
//            Text(npub("9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33"))
//            Text(lnurl ?? "")
            Text("prefix: \(s.prefix)")
            Divider()
            Text("pubkey: \(s.pubkey ?? "")")
            Divider()
            Text("eventId: \(s.eventId ?? "")")
            Divider()
            if let kind = s.kind {
            Text("kind: \(String(format: "%d", kind))")
            Divider()
            }
            Text("Relays:")
            ForEach(s.relays, id:\.self) { r in
                Text(r)
            }
            .onAppear {
                if let naddr = try? ShareableIdentifier(prefix: "naddr", kind: 30023, pubkey: "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93", dTag: "1680612926599") {
                    print(naddr.bech32string)
                }
                
                if let nevent = try? ShareableIdentifier(prefix: "nevent", kind: 1, pubkey: "d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a", eventId: "64df6fe7512fee4318728f8704c82a86926c8e0ec1eef7613ed066d840d16b79") {
                    print(nevent.bech32string)
                }
            }
        }
        else {
            Text("gmmm broken \(error)")
        }
    }
}

struct ShareableIdentifierTest_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ShareableIdentifierTest()
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}



