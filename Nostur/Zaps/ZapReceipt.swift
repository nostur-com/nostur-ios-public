//
//  ZapReceipt.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/10/2023.
//

import SwiftUI

struct ZappedFromName: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @ObservedObject var settings: SettingsStore = .shared
    private var context: String = "Default"
    
    init(pubkey: String, nrPost: NRPost, context: String = "Default") {
        self.nrPost = nrPost
        self.nrContact = NRContact.instance(of: pubkey) // fromPubkey, not nrPost.pubkey (zapper/wallet)
        self.context = context
    }
    
    
    
    var body: some View {
        HStack {
            Text(nrContact.anyName)
                .foregroundColor(.primary)
                .fontWeightBold()
                .contentTransitionOpacity()
                .lineLimit(1)
                .layoutPriority(2)
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: context)
                }
            
            PossibleImposterLabelView(nrContact: nrContact)
            
            Ago(nrPost.createdAt)
                .equatable()
                .layoutPriority(2)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if settings.displayUserAgentEnabled, let via = nrPost.via {
                Text(String(format: "via %@", via))
                    .font(.subheadline)
                    .lineLimit(1)
                    .layoutPriority(3)
                    .foregroundColor(.secondary)
            }
        }
    }
}
