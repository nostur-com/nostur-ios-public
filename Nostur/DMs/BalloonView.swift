//
//  BalloonView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/12/2025.
//

import SwiftUI
import NavigationBackport

struct BalloonView17: View {
    @ObservedObject public var nrChatMessage: NRChatMessage
    public var accountPubkey: String
    public var showPFP: Bool = false
    private var isSentByCurrentUser: Bool {
        nrChatMessage.pubkey == accountPubkey
    }
    
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    @State private var showDMSendResult: RecipientResult? = nil
    
    var body: some View {
        HStack {
            if isSentByCurrentUser {
                Spacer()
            }
            else if showPFP {
                ObservedPFP(nrContact: nrChatMessage.nrContact, size: 20)
                    .offset(x: 5, y: 5)
            }
            DMContentRenderer(pubkey: nrChatMessage.pubkey, contentElements: nrChatMessage.contentElementsDetail, availableWidth: availableWidth, isSentByCurrentUser: isSentByCurrentUser)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSentByCurrentUser ? theme.accent : theme.background)
                )
                .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(isSentByCurrentUser ? theme.accent : theme.background)
                        .scaleEffect(x: isSentByCurrentUser ? 1 : -1)
                        .rotationEffect(.degrees(isSentByCurrentUser ? 35 : -35))
                        .offset(x: isSentByCurrentUser ? 10 : -10, y: 0)
                        .font(.system(size: 25))
                }
                .padding(.horizontal, 10)
                .padding(isSentByCurrentUser ? .leading : .trailing, 50)
                .overlay(alignment: isSentByCurrentUser ? .bottomLeading : .bottomTrailing) {
                    Text(nrChatMessage.createdAt, format: .dateTime.hour().minute())
                        .frame(alignment: isSentByCurrentUser ? .leading : .trailing)
                        .font(.footnote)
                        .foregroundColor(nrChatMessage.nEvent.kind == .legacyDirectMessage ? .secondary : .primary)
                        .padding(.bottom, 8)
                        .padding(isSentByCurrentUser ? .leading : .trailing, 5)
                }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 2) {
               
                Spacer()
                
                ForEach(Array(nrChatMessage.dmSendResult.keys).sorted(), id: \.self) { pubkey in
                    RecipientResultView(result: nrChatMessage.dmSendResult[pubkey]!)
                        .onTapGesture {
                            showDMSendResult = nrChatMessage.dmSendResult[pubkey]!
                        }
                }
            }
            .frame(height: 12)
            .padding(.trailing, 25)
            .padding(.bottom, 2)
        }
        .sheet(item: $showDMSendResult) { dmSendResult in
            NBNavigationStack {
                DMSendResultDetail(
                    dmSentResult: dmSendResult,
                    isOwnRelays: accountPubkey == dmSendResult.recipientPubkey
                )
            }
        }
    }
}
