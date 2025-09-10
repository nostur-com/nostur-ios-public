//
//  PossibleImposterLabel.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2024.
//

import SwiftUI
import NavigationBackport

struct PossibleImposterLabelView: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var nrContact: NRContact
    
    var body: some View {
        if let similarToPubkey = nrContact.similarToPubkey {
            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                .padding(.horizontal, 8)
                .background(.red)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 3)
                .layoutPriority(2)
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: nrContact.pubkey, similarToPubkey: similarToPubkey))
                }
        }
        else {
            Rectangle()
                .frame(width: 0, height: 0)
                .hidden()
                .onAppear {
                    nrContact.runImposterCheck()
                }
        }
    }
}

struct PossibleImposterLabelView2: View {
    @Environment(\.theme) private var theme

    @ObservedObject private var nrContact: NRContact

    init(pubkey: String) {
        self.nrContact = NRContact.instance(of: pubkey)
    }
    
    init(nrContact: NRContact) {
        self.nrContact = nrContact
    }
    
    var body: some View {
        if let similarToPubkey = nrContact.similarToPubkey {
            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                .padding(.horizontal, 8)
                .background(.red)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 3)
                .layoutPriority(2)
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: nrContact.pubkey, similarToPubkey: similarToPubkey))
                }
        }
        else {
            Rectangle()
                .frame(width: 0, height: 0)
                .hidden()
                .onAppear {
                    nrContact.runImposterCheck()
                }
        }
    }
}

struct PossibleImposterDetail: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    private var possibleImposterPubkey: String
    private var followingPubkey: String? = nil
    
    
    @ObservedObject private var possibleImposterNRContact: NRContact
    @State private var followingContact: NRContact? = nil
    
    init(possibleImposterPubkey: String, possibleImposterNRContact: NRContact? = nil, followingPubkey: String? = nil) {
        self.possibleImposterNRContact = possibleImposterNRContact ?? NRContact.instance(of: possibleImposterPubkey)
        self.possibleImposterPubkey = possibleImposterPubkey
        self.followingPubkey = followingPubkey
    }
    
    var body: some View {
        VStack {
            VStack {
                NRProfileRow(withoutFollowButton: true, tapEnabled: false, showNpub: true, nrContact: possibleImposterNRContact)
                    .overlay(alignment: .topTrailing) {
                        ImposterLabelToggle(nrContact: possibleImposterNRContact)
                            .padding(.trailing, 5)
                            .padding(.top, 5)
                    }
                FollowedBy(pubkey: possibleImposterNRContact.pubkey, alignment: .trailing, minimal: false, showZero: true)
                    .padding(10)
            }
            .background(theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.regularMaterial, lineWidth: 1)
            )
            .padding(10)
            
            Text("The profile above was found to be similar to one below that you are already following:")
                .padding(.horizontal, 20)

            if let followingContact {
                VStack {
                    NRProfileRow(tapEnabled: false, showNpub: true, nrContact: followingContact)
                    FollowedBy(pubkey: followingContact.pubkey, alignment: .trailing, minimal: false, showZero: true)
                        .padding(10)
                }
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
                .padding(10)
            }
            else {
                ProgressView()
                    .padding(10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(String(localized: "Possible imposter", comment: "Navigation title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Close") { dismiss() }
            }
        }
        .task {
            if let followingPubkey {
                followingContact = NRContact.instance(of: followingPubkey)
            }
            else {
                possibleImposterNRContact.runImposterCheck()
            }
        }
    }
}

struct ImposterLabelToggle: View {
    @ObservedObject public var nrContact: NRContact
    @State private var addBackSimilarToPubkey: String? = nil
    
    var body: some View {
        if nrContact.couldBeImposter == 1 {
            Button {
                withAnimation {
                    nrContact.couldBeImposter = 0
                    if nrContact.similarToPubkey != nil {
                        addBackSimilarToPubkey = nrContact.similarToPubkey
                    }
                    nrContact.similarToPubkey = nil
                }
            } label: {
                Text("Remove imposter label", comment: "Button to remove 'possible imposter' label from a contact")
                    .font(.caption)
            }
            .padding(.trailing, 10)
        }
        else {
            Button {
                withAnimation {
                    nrContact.couldBeImposter = 1
                    nrContact.similarToPubkey = addBackSimilarToPubkey
                }
            } label: {
                Text("Add back", comment: "Button to add back 'possible imposter' label from a contact (only visible right after removing)")
                    .font(.caption)
            }
            .padding(.trailing, 10)
        }
    }
}
