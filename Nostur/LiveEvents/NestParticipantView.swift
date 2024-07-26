//
//  ParticipantView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/07/2024.
//

import SwiftUI

struct NestParticipantView: View {
    
    @ObservedObject public var nrContact: NRContact
    public var role: String? = nil
    public let aTag: String
    
    // Toggle controls, like mute
    @State private var showControls = false
    
    var body: some View {
        VStack(spacing: 2.0) {
            PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                .overlay(alignment: .topLeading) {
                    if nrContact.raisedHand {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 35)) // Adjust size as needed
                            .foregroundColor(.orange) // Change the color as needed
                            .offset(x: -20.0, y: -12)
                            .rotationEffect(.degrees(-15))
                            .symbolEffectPulse()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showControls {
                        MicButton()
                            .offset(x: 15.0, y: 5)
                    }
                }
            Text(nrContact.anyName).lineLimit(1)
            Text(role ?? "").font(.footnote)
                .foregroundColor(.secondary)
                .opacity(role != nil ? 1.0 : 0.0)
            
        }
        .frame(maxWidth: 90.0)
        .onAppear {
            nrContact.listenForPresence(aTag)
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        if let nrContact = PreviewFetcher.fetchNRContact() {
            NestParticipantView(nrContact: nrContact, role: "Moderator", aTag: "30311:07c058945239c541e7875ec21285e89d53afacc34a8e81b2c5ecdf028c198729:07056f33-cd48-4126-8b2e-ee68eeefafd9")
        }
    }
}


struct MicButton: View {
    var body: some View {
        ZStack {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "mic")
                        .font(.system(size: 20))
                        .foregroundColor(.white) 
                }
    }
}
