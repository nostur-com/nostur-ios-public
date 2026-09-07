//
//  DMSendResultDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI
import NavigationBackport

struct DMSendResultDetail: View {
    @Environment(\.dismiss) var dismiss
    let dmSentResult: RecipientResult
    let isOwnRelays: Bool
    @State private var showGiftWrap = false
    
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

            if dmSentResult.giftWrapDetails != nil {
                Button("Message source") {
                    showGiftWrap = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
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
        .sheet(isPresented: $showGiftWrap) {
            if let details = dmSentResult.giftWrapDetails {
                NBNavigationStack {
                    DMGiftWrapJSONSheet(details: details, layer: .giftWrap, close: { showGiftWrap = false })
                }
            }
        }
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

private struct DMGiftWrapJSONSheet: View {
    enum Layer {
        case giftWrap, seal, rumor

        var title: LocalizedStringKey {
            switch self {
            case .giftWrap: return "Giftwrap"
            case .seal: return "Seal"
            case .rumor: return "Rumor"
            }
        }
    }

    @Environment(\.theme) private var theme
    let details: DMGiftWrapDetails
    let layer: Layer
    let close: () -> Void
    @State private var json = ""

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .toolbar {
                    closeToolbarItem
                    copyToolbarItem
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                    nextLayerToolbarItem
                }
        }
        else {
            content
                .toolbar {
                    closeToolbarItem
                    copyToolbarItem
                    nextLayerToolbarItem
                }
        }
    }

    private var content: some View {
        PostRawJSONTextView(text: json, textColor: theme.primary, accentColor: theme.accent)
            .background(theme.listBackground)
            .navigationTitle(layer.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let event = switch layer {
                case .giftWrap: details.giftWrap
                case .seal: details.seal
                case .rumor: details.rumor
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                if let data = try? encoder.encode(event), let text = String(data: data, encoding: .utf8) {
                    json = text
                }
            }
    }

    private var closeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark", action: close)
        }
    }

    private var copyToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                UIPasteboard.general.string = json
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(json.isEmpty)
        }
    }

    private var nextLayerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if layer != .rumor {
                NavigationLink {
                    DMGiftWrapJSONSheet(details: details, layer: layer == .giftWrap ? .seal : .rumor, close: close)
                } label: {
                    HStack(spacing: 4) {
                        Text(layer == .giftWrap ? "Seal" : "Rumor")
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
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
