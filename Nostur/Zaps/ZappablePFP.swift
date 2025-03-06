//
//  ZappablePFP.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/07/2023.
//

import SwiftUI
import Combine

// PFP with animation when zapped
struct ZappablePFP: View {
    let pubkey: String
    @ObservedObject public var pfpAttributes: PFPAttributes
    var size: CGFloat
    var zapEtag: String?
    var zapAtag: String?
    var forceFlat: Bool?
    @State private var isZapped: Bool = false
    @State private var animate = false
    @State private var opacity: Double = 0.0
    
    init(pubkey: String, pfpAttributes: PFPAttributes, size: CGFloat = 50.0, zapEtag: String? = nil, zapAtag: String? = nil, forceFlat: Bool? = nil) {
        self.pubkey = pubkey
        self.pfpAttributes = pfpAttributes
        self.size = size
        self.zapEtag = zapEtag
        self.zapAtag = zapAtag
        self.forceFlat = forceFlat
    }
    
    init(pubkey: String, contact: NRContact, size: CGFloat = 50.0, zapEtag: String? = nil, zapAtag: String? = nil, forceFlat: Bool? = nil) {
        self.pubkey = pubkey
        self.pfpAttributes = PFPAttributes(contact: contact, pubkey: contact.pubkey)
        self.size = size
        self.zapEtag = zapEtag
        self.zapAtag = zapAtag
        self.forceFlat = forceFlat
    }
    
    var body: some View {
        PFP(pubkey: pubkey, pictureUrl: pfpAttributes.pfpURL, size: size, forceFlat: (forceFlat ?? false))
            .overlay(alignment: .center) {
                if isZapped {
                    Circle()
                        .stroke(lineWidth: 4.5)
                        .fill(Color.yellow)
                        .frame(width: size, height: size)
                        .opacity(self.opacity)
                        .animation(.easeIn(duration: 3.0), value: self.opacity)
                    ForEach(0..<10) { i in
                        Circle()
                            .stroke(lineWidth: 2.5)
                            .fill(Color.yellow.opacity(Double.random(in: 0.12...0.5)))
                            .frame(width: size, height: size)
                            .scaleEffect(animate ? 0.9 : 1.25)
                            .opacity(animate ? 1 : 0.5)
                            .animation(.easeInOut(duration: Double.random(in: 0.1...0.55)).repeatCount(6), value: animate)
                            .overlay(
                                Circle()
                                    .trim(from: CGFloat(Double.random(in: 0.7...0.95)), to: CGFloat(Double.random(in: 0.42...93)))
                                
                                    .stroke(style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                                    .rotationEffect(.degrees(animate ? 360 : 0))
                                    .animation(.linear(duration: Double.random(in: 0.15...0.35)).repeatCount(9), value: animate)
                            )
                            .foregroundColor(Color.yellow)
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
            }
            .onChange(of: pfpAttributes.contact) { contact in
                guard let contact = pfpAttributes.contact else { return }
                guard let zapState = contact.zapState else { return }

                isZapped = [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapState)
            }
            .onAppear {
                guard let contact = pfpAttributes.contact else { return }
                guard let zapState = contact.zapState else { return }

                isZapped = [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapState)
            }
            .onReceive(ViewUpdates.shared.zapStateChanged.receive(on: RunLoop.main)) { zapStateChange in
                if let thisEtag = self.zapEtag {
                    guard thisEtag == zapStateChange.eTag else { return }
                    guard zapStateChange.pubkey == pubkey else { return}
                    isZapped = [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapStateChange.zapState)
                }
                else if let thisAtag = self.zapAtag {
                    guard zapStateChange.pubkey == pubkey else { return}
                    guard thisAtag == zapStateChange.aTag else { return }
                    isZapped = [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapStateChange.zapState)
                }
            }
    }
}

struct ZappablePreviews: View {
    
    @State var contact1 = PreviewFetcher.fetchNRContact()
    @State var contact2 = PreviewFetcher.fetchNRContact()
    @State var contact3 = PreviewFetcher.fetchNRContact()
    @State var contact4 = PreviewFetcher.fetchNRContact()
    
    @State var zapped1 = false
    @State var zapped2 = false
    @State var zapped3 = false
    @State var zapped4 = false
    
    
    var body: some View {
        VStack(spacing: 15.0) {
            if let contact = contact1 {
                let pfpAttributes = PFPAttributes(contact: contact, pubkey: contact.pubkey)
                ZappablePFP(pubkey: contact.pubkey, pfpAttributes: pfpAttributes)
                    .onTapGesture {
                        contact.zapState = .initiated
                    }
            }
            
            if let contact = contact2 {
                let pfpAttributes = PFPAttributes(contact: contact, pubkey: contact.pubkey)
                ZappablePFP(pubkey: contact.pubkey, pfpAttributes: pfpAttributes)
                    .onTapGesture {
                        contact.zapState = .initiated
                    }
            }
            
            if let contact = contact3 {
                let pfpAttributes = PFPAttributes(contact: contact, pubkey: contact.pubkey)
                ZappablePFP(pubkey: contact.pubkey, pfpAttributes: pfpAttributes)
                    .onTapGesture {
                        contact.zapState = .initiated
                    }
            }
            
            if let contact = contact4 {
                let pfpAttributes = PFPAttributes(contact: contact, pubkey: contact.pubkey)
                ZappablePFP(pubkey: contact.pubkey, pfpAttributes: pfpAttributes)
                    .onTapGesture {
                        contact.zapState = .initiated
                    }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            ZappablePreviews()
        }
    }
}
