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
    let pubkey:String
    var contact:NRContact?
    var size:CGFloat = 50.0
    var zapEtag:String?
    @State private var isZapped:Bool = false
    @State private var subscriptions = Set<AnyCancellable>()
    
    @State private var animate = false
    @State private var opacity:Double = 0.0
    
    var body: some View {
        PFP(pubkey: pubkey, nrContact: contact, size: size)
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
            .onAppear {
                guard let contact = contact else { return }
                DataProvider.shared().bg.perform {
                    if let zapState = contact.contact.zapState {
                        if [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapState) {
                            DispatchQueue.main.async {
                                contact.zappableAttributes.isZapped = true
                                isZapped = true
                            }
                        }
                        else {
                            DispatchQueue.main.async {
                                isZapped = false
                                contact.zappableAttributes.isZapped = false
                            }
                        }
                    }
                    contact.contact.zapStateChanged
                        .sink { (zapState, zapEtag) in
                            DispatchQueue.main.async {
                                if let zapState = zapState,
//                                   let zapEtag = zapEtag,
                                   [.initiated,.nwcConfirmed,.zapReceiptConfirmed].contains(zapState) {
                                    isZapped = true
                                }
                                else {
                                    isZapped = false
                                }
                            }
                        }
                        .store(in: &subscriptions)
                }
            }
            .transaction { t in
                t.animation = nil
                t.disablesAnimations = true
            }
//            .id(pubkey)
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
                ZappablePFP(pubkey: contact.pubkey, contact: contact)
                    .onTapGesture {
                        contact.zappableAttributes.zapState = .initiated
                    }
            }
            
            if let contact = contact2 {
                ZappablePFP(pubkey: contact.pubkey, contact: contact)
                    .onTapGesture {
                        contact.zappableAttributes.zapState = .initiated
                    }
            }
            
            if let contact = contact3 {
                ZappablePFP(pubkey: contact.pubkey, contact: contact)
                    .onTapGesture {
                        contact.zappableAttributes.zapState = .initiated
                    }
            }
            
            if let contact = contact4 {
                ZappablePFP(pubkey: contact.pubkey, contact: contact)
                    .onTapGesture {
                        contact.zappableAttributes.zapState = .initiated
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
