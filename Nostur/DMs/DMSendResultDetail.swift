//
//  DMSendResultDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI

struct DMSendResultDetail: View {
    @Environment(\.dismiss) var dismiss
    let dmSentResult: RecipientResult
    let isOwnRelays: Bool
    
    var body: some View {
        VStack {
            if dmSentResult.relayResults.isEmpty {
                HStack(spacing: 3) {
                    Text("No DM relays found for")
                    ContactName(pubkey: dmSentResult.recipientPubkey)
                }
                .fontWeightBold()
            }
            else if isOwnRelays {
                Text("Delivery to your DM relays (back-up):")
                    .fontWeightBold()
            }
            else {
                HStack(spacing: 3) {
                    Text("Delivery to relays of")
                    ContactName(pubkey: dmSentResult.recipientPubkey)
                }
                .fontWeightBold()
            }
            
            Color.clear.frame(height: 20)
            
            ForEach(dmSentResult.relayResults.keys.sorted(), id: \.self) { key in
                HStack {
                    Image(systemName: iconName(for: dmSentResult.relayResults[key]!))
                        .foregroundStyle(color(for: dmSentResult.relayResults[key]!))
                        .frame(width: 24, alignment: .center)
                    
                    if dmSentResult.relayResults[key]! == .timeout {
                        Text("\(key) (Timeout or other error)")
                    }
                    else {
                        Text(key)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .navigationTitle("Message Delivery")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func iconName(for result: DMSendResult) -> String {
        switch result {
        case .success:
            return "checkmark.circle.fill"
        case .timeout:
            return "exclamationmark.triangle.fill"
        case .sending:
            return "hourglass.tophalf.filled"
        }
    }
    
    private func color(for result: DMSendResult) -> Color {
        switch result {
        case .success:
            return Color.green
        case .timeout:
            return Color.red
        case .sending:
            return Color.gray
        }
    }
}

struct RecipientResultView: View {
    @ObservedObject var result: RecipientResult
    
    var body: some View {
        Image(systemName: iconName(for: result))
            .resizable()
            .scaledToFit()
            .foregroundStyle(iconColor(for: result))
    }
    
    func iconName(for result: RecipientResult) -> String {
        if result.allFailed {
            return "xmark.circle.fill"
        }
        if result.anySuccess {
            return "checkmark.circle.fill"
        }
        return "checkmark.circle"
    }
    
    func iconColor(for result: RecipientResult) -> Color {
        if result.allFailed {
            return Color.red
        }
        if result.anySuccess {
            return Color.green
        }
        return Color.gray
    }
}

#Preview("DMSendResultDetail") {
    VStack {
        DMSendResultDetail(
            dmSentResult: RecipientResult(
                recipientPubkey: "9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33",
                relayResults: [
                    "wss://nos.lol": DMSendResult.sending,
                    "wss://relay.nostr.band": DMSendResult.timeout,
                    "wss://nostr.wine":DMSendResult.success
                ]
            ),
            isOwnRelays: false
        )
        
        DMSendResultDetail(
            dmSentResult: RecipientResult(
                recipientPubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
                relayResults: [
                    "wss://nos.lol": DMSendResult.timeout,
                    "wss://relay.nostr.band": DMSendResult.timeout,
                    "wss://nostr.wine":DMSendResult.sending
                ]
            ),
            isOwnRelays: true
        )
    }
}
