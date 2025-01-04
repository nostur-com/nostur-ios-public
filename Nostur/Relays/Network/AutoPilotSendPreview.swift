//
//  AutoPilotSendPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/09/2024.
//

import SwiftUI

struct AutoPilotSendPreview: View {
    
    public let nEvent: NEvent
    
    @StateObject private var vm = RelayAutoPilotPreviewModel()
    
    var body: some View {
        ZStack {
            if !vm.relays.isEmpty {
                VStack(alignment: .leading) {
                    Text("Autopilot will broadcast to the following additional relays")
                    ForEach(vm.relays, id: \.self) { relay in
                        Text("\(relay)")
                    }
                }
                .font(.footnote)
                .padding(5)
                
                
            }
        }
        .onAppear {
            vm.runCheck(nEvent)
        }
    }
}

#Preview {
    let message = ###"["EVENT", "example", {"created_at":1726659460,"tags":[["e","78913932684888ca6a560991b58dd9e64f49d106656e12071f17b441ab82dc28","","root"],["e","84e34d14f9d17efc6fb77c3ebf6310fac42dc78b73a96c575d91d56cd2739afd","","reply"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"id":"c445fe4bf1b1c322ead98a2af21c070b32ef173f33d544a578d3ea776d769d00","content":"but how would you increase the target difficulty? ","kind":1,"sig":"89a40fbd471c55c2ff9ab0f8746e0a72e34e9e8dc11c82a18aba5c9d97d7dcf13f341204b21394f9a795e54e56a2ca7de9192f186ea11309e78ceb35a4fcb481","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"}]"###
    let examplePost = try? RelayMessage.parseRelayMessage(text: message, relay: "PreviewCanvas")
    
    return VStack {
        if let nEvent = examplePost?.event {
            AutoPilotSendPreview(nEvent: nEvent)
        }
        Text("Preview?")
    }
}
