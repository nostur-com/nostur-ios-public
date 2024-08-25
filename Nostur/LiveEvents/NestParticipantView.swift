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
    
    public var showControls = true
    
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
                .overlay(alignment: .bottomTrailing) {
                    if showControls && nrContact.volume > 0 {
                        MicButton(volume: nrContact.volume, isMuted: nrContact.isMuted)
                            .offset(x: 15.0, y: 5)
                    }
                }
                .onTapGesture {
                    navigateTo(nrContact)
                }
            Text(nrContact.anyName).lineLimit(1)
            Text(role ?? "").font(.footnote)
                .foregroundColor(.secondary)
                .opacity(role != nil ? 1.0 : 0.0)
            
        }
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
            let _ = nrContact.volume = 0.25
            NestParticipantView(nrContact: nrContact, role: "Moderator", aTag: "30311:07c058945239c541e7875ec21285e89d53afacc34a8e81b2c5ecdf028c198729:07056f33-cd48-4126-8b2e-ee68eeefafd9")
        }
    }
}


struct MicButton: View {
    public var volume: CGFloat
    public var isMuted: Bool
    
    var body: some View {
        ZStack(alignment: .center) {
            Circle()
                .fill(Color.gray)
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottom) {
                    Color.accentColor
                        .frame(height: 28*(min(volume+(volume > 0.125 ? 0.25 : 0), 1.0)))
                        .animation(.interpolatingSpring(stiffness: 400, damping: 3), value: volume)
                }
                
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
        }
        .clipShape(Circle())
    }
}
