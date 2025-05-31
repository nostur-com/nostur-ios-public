//
//  LiveEventPFP.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2024.
//

import SwiftUI

// Copy paste and altered from ZappablePFP
struct LiveEventPFP: View {
    private let pubkey: String
    @StateObject private var pfpAttributes: PFPAttributes
    private var size: CGFloat = 50.0
    private var forceFlat = false
    
    init(pubkey: String, pfpAttributes: PFPAttributes, size: CGFloat, forceFlat: Bool = false) {
        self.pubkey = pubkey
        _pfpAttributes = StateObject(wrappedValue: pfpAttributes)
        self.size = size
        self.forceFlat = forceFlat
        self.animate = animate
        self.opacity = opacity
    }
    
    @State private var animate = false
    @State private var opacity: Double = 0.0
    
    var body: some View {
        PFP(pubkey: pubkey, pictureUrl: pfpAttributes.pfpURL, size: size, forceFlat: forceFlat)
            .overlay(alignment: .center) {
                Circle()
                    .stroke(lineWidth: 4.5)
                    .fill(Color.purple)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_WIDTH)
                    .opacity(self.opacity)
                    .animation(.easeIn(duration: 15.0), value: self.opacity)
                ForEach(0..<10) { i in
                    Circle()
                        .stroke(lineWidth: 2.5)
                        .fill(Color.purple.opacity(Double.random(in: 0.12...0.5)))
                        .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_WIDTH)
                        .scaleEffect(animate ? 0.9 : 1.25)
                        .opacity(animate ? 1 : 0.5)
                        .animation(.easeInOut(duration: Double.random(in: 0.5...1.5)).repeatCount(16), value: animate)
                        .overlay(
                            Circle()
                                .trim(from: CGFloat(Double.random(in: 4...15)), to: CGFloat(Double.random(in: 0.42...93)))
                            
                                .stroke(style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                                .rotationEffect(.degrees(animate ? 360 : 0))
                                .animation(.linear(duration: Double.random(in: 0.15...0.35)).repeatCount(19), value: animate)
                        )
                        .foregroundColor(Color.purple)
                        .onAppear() {
                            self.animate = true
                            self.opacity = 1.0
                        }
                        .onDisappear {
                            self.animate = false
                            self.opacity = 0.0
                        }
                }
            }
            .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
            .overlay(alignment: .bottom) {
                ZStack {
                    Circle()
                        .fill(Color.purple)
                    Image(systemName: "waveform")
                        .foregroundColor(.white)
                        .padding(2)
                }
                .frame(width: 20, height: 20)
                .symbolEffectPulse()
                .offset(y: 10)
            }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        if let nrContact = PreviewFetcher.fetchNRContact() {
            let pfpAttributes = PFPAttributes(contact: nrContact, pubkey: nrContact.pubkey)
            LiveEventPFP(pubkey: nrContact.pubkey, pfpAttributes: pfpAttributes, size: 50, forceFlat: false)
        }
    }
}
