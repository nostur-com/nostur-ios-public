//
//  ProfileRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/01/2023.
//

import SwiftUI

struct ProfileCardByPubkey: View {
    @Environment(\.theme) private var theme
    public let pubkey: String
    @StateObject private var vm = FetchVM<Contact>(timeout: 2.5, debounceTime: 0.05)
    @State var fixedPfp: URL?
    
    var body: some View {
        Group {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task { [weak vm] in
                        guard let vm else { return }
                        vm.setFetchParams((
                            prio: false,
                            req: { [weak vm] _ in
                                guard let vm else { return }
                                if let contact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().viewContext) { // 1. CHECK LOCAL DB
                                    vm.ready(contact)
                                }
                                else { // 2. ELSE CHECK RELAY
                                    req(RM.getUserMetadata(pubkey: pubkey))
                                }
                            },
                            onComplete: { [weak vm] relayMessage, _ in // TODO: Should make compatible with Contact also instead of just Event
                                DispatchQueue.main.async {
                                    guard let vm else { return }
                                    if case .ready(_) = vm.state { return }
                                    
                                    if let contact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().viewContext) { // 3. WE FOUND IT ON RELAY
                                        vm.ready(contact)
                                    }
                                    else { // 4. TIME OUT
                                        vm.timeout()
                                    }
                                }
                            },
                            altReq: nil
                            
                        ))
                        vm.fetch()
                    }
            case .ready(let contact):
                ProfileRow(contact: contact)
            case .timeout:
                Text("Unable to fetch profile")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.lineColor, lineWidth: 1)
        )
        .clipped()
    }
}

struct ProfileRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject private var fg: FollowingGuardian = .shared
     
    public var withoutFollowButton = false
    public var tapEnabled: Bool = true
    public var showNpub: Bool = false
    @ObservedObject public var contact: Contact
    
    @State private var similarToPubkey: String? = nil
    @State private var fixedPfp: URL?

    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfp {
                        FixedPFP(picture: fixedPfp)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(contact.anyName).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let similarToPubkey {
                            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                .padding(.horizontal, 8)
                                .background(.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.top, 3)
                                .layoutPriority(2)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: contact.pubkey, similarToPubkey: similarToPubkey))
                                }
                            Text(contact.npub)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        else if contact.nip05veried, let nip05 = contact.nip05 {
                            NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if showNpub {
                            Text(contact.npub)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        if let fixedName = contact.fixedName, fixedName != contact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        contact.fixedName = contact.anyName
                                    }
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                    if (!withoutFollowButton) {
                        FollowButton(pubkey: contact.pubkey)
                            .buttonStyle(.borderless)
                    }
                }
                Text(contact.about ?? "").foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            guard tapEnabled else { return }
            navigateTo(ContactPath(key: contact.pubkey), context: containerID)
        }
        .task { [weak contact] in
            guard let contact else { return }
            
            if let fixedPfp = contact.fixedPfp,
               fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp),
                hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
            {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
            
            ImposterChecker.shared.runImposterCheck(contact: contact) { imposterYes in
                self.similarToPubkey = imposterYes.similarToPubkey
            }
            
            if let fixedPfp = contact.fixedPfp,
                fixedPfp != contact.picture,
               let fixedPfpUrl = URL(string: fixedPfp) {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
        }
    }
}

struct NRProfileRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject private var fg: FollowingGuardian = .shared
     
    public var withoutFollowButton = false
    public var tapEnabled: Bool = true
    public var showNpub: Bool = false
    @ObservedObject public var nrContact: NRContact

    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                .overlay(alignment: .bottomTrailing) {
                    if let fixedPfpURL = nrContact.fixedPfpURL {
                        FixedPFP(picture: fixedPfpURL)
                    }
                }
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(nrContact.anyName).font(.headline).foregroundColor(.primary)
                            .lineLimit(1)
                        
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
                            Text(nrContact.npub ?? "")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .opacity(nrContact.npub != nil ? 1 : 0)
                                .task {
                                    await nrContact.loadNpub()
                                }
                        }
                        else if nrContact.similarToPubkey == nil && nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                .layoutPriority(3)
                        }
                        
                        if nrContact.similarToPubkey == nil && showNpub {
                            Text(nrContact.npub ?? "")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .opacity(nrContact.npub != nil ? 1 : 0)
                                .task {
                                    await nrContact.loadNpub()
                                }
                        }
                        
                        if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                            HStack {
                                Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                Image(systemName: "multiply.circle.fill")
                                    .onTapGesture {
                                        nrContact.setFixedName(nrContact.anyName)
                                    }
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer()
                    if (!withoutFollowButton) {
                        FollowButton(pubkey: nrContact.pubkey)
                            .buttonStyle(.borderless)
                    }
                }
                Text(nrContact.about ?? "").foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            guard tapEnabled else { return }
            navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
        }
        .onAppear {
            nrContact.runImposterCheck()
        }
    }
}

struct ProfileRow_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            ScrollView {
    //            let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
                
                if let contact = PreviewFetcher.fetchContact() {
                    
                    LazyVStack {
                        ProfileRow(contact: contact)
                        
                        ProfileRow(contact: contact)
                        
                        ProfileRow(contact: contact)
                        
                        Spacer()
                    }
                }
            }
        }
    }
}
