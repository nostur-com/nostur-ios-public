//
//  PossibleImposterLabel.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2024.
//

import SwiftUI
import NavigationBackport

struct PossibleImposterLabel: View {
    @EnvironmentObject private var themes: Themes
    public var possibleImposterPubkey: String
    public var followingPubkey: String? = nil
    @State private var showDetails: Bool = false
    
    var body: some View {
        Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
            .padding(.horizontal, 8)
            .background(.red)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.top, 3)
            .layoutPriority(2)
            .contentShape(Rectangle())
            .onTapGesture {
                sendNotification(.showImposterDetails, ImposterDetails(pubkey: possibleImposterPubkey, similarToPubkey: followingPubkey))
            }
    }
}

struct NewPossibleImposterLabel: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject private var pfp: PFPAttributes
    @State private var showDetails: Bool = false
    
    init(pfp: PFPAttributes) {
        self.pfp = pfp
    }
    
    init(nrContact: NRContact) {
        self.pfp = PFPAttributes(contact: nrContact, pubkey: nrContact.pubkey)
    }
    
    var body: some View {
        if let similarToPubkey = pfp.similarToPubkey {
            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                .padding(.horizontal, 8)
                .background(.red)
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 3)
                .layoutPriority(2)
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: pfp.pubkey, similarToPubkey: similarToPubkey))
                }
        }
        else {
            Rectangle()
                .frame(width: 0, height: 0)
                .hidden()
                .onAppear {
                    pfp.runImposterCheck()
                }
        }
    }
}

struct PossibleImposterDetail: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    public var possibleImposterPubkey: String
    public var followingPubkey: String? = nil
    
    
    @State private var possibleImposterContact: Contact? = nil
    @State private var followingContact: Contact? = nil
    
    var body: some View {
        VStack {
            if let possibleImposterContact {
                VStack {
                    ProfileRow(withoutFollowButton: true, tapEnabled: false, contact: possibleImposterContact)
                        .overlay(alignment: .topTrailing) {
                            ImposterLabelToggle(contact: possibleImposterContact)
                                .padding(.trailing, 5)
                                .padding(.top, 5)
                        }
                    FollowedBy(pubkey: possibleImposterContact.pubkey, alignment: .trailing, minimal: false, showZero: true)
                        .padding(10)
                }
                .background(themes.theme.background)
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
            
            Text("The profile above was found to be similar to one below that you are already following:")
                .padding(.horizontal, 20)

            if let followingContact {
                VStack {
                    ProfileRow(tapEnabled: false, showNpub: true, contact: followingContact)
                    FollowedBy(pubkey: followingContact.pubkey, alignment: .trailing, minimal: false, showZero: true)
                        .padding(10)
                }
                .background(themes.theme.background)
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
            possibleImposterContact = Contact.fetchByPubkey(possibleImposterPubkey, context: context())
            if let followingPubkey {
                followingContact = Contact.fetchByPubkey(followingPubkey, context: context())
            }
            else {
                guard let mainContact = possibleImposterContact else { return }
                guard let followingCache = AccountsState.shared.loggedInAccount?.followingCache else { return }

                let contactAnyName = mainContact.anyName.lowercased()
                let currentAccountPubkey = AccountsState.shared.activeAccountPublicKey
                let cPubkey = mainContact.pubkey
                guard let cPic = mainContact.pictureUrl else { return }

                bg().perform {
                    guard let account = account() else { return }
                    guard account.publicKey == currentAccountPubkey else { return }
                    guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                        pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                    }) else { return }
                    
                    guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                    Task.detached(priority: .background) {
                        let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                        guard similarPFP else {
                            // TODO: Remove progress spinner
                            return
                        }
                        DispatchQueue.main.async {
                            guard currentAccountPubkey == AccountsState.shared.activeAccountPublicKey else { return }
                            mainContact.similarToPubkey = followingPubkey
                            followingContact = Contact.fetchByPubkey(followingPubkey, context: context())
                        }
                    }
                }
            }
        }
    }
}

struct ImposterLabelToggle: View {
    @ObservedObject public var contact: Contact
    @State private var addBackSimilarToPubkey: String? = nil
    
    var body: some View {
        if contact.couldBeImposter == 1 {
            Button {
                withAnimation {
                    contact.couldBeImposter = 0
                    addBackSimilarToPubkey = contact.similarToPubkey
                    contact.similarToPubkey = nil
                }
                save()
            } label: {
                Text("Remove imposter label", comment: "Button to remove 'possible imposter' label from a contact")
                    .font(.caption)
            }
        }
        else {
            Button {
                withAnimation {
                    contact.couldBeImposter = 1
                    contact.similarToPubkey = addBackSimilarToPubkey
                }
                save()
            } label: {
                Text("Add back", comment: "Button to add back 'possible imposter' label from a contact (only visible right after removing)")
                    .font(.caption)
            }
        }
    }
}


#Preview {
    PreviewContainer({ pe in pe.loadContacts() }) {
        NBNavigationStack {
            PossibleImposterLabel(possibleImposterPubkey: "", followingPubkey: "")
        }
    }
}
