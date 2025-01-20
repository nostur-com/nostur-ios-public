//
//  QuotedNoteFragmentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct QuotedNoteFragmentView: View {
    @ObservedObject private var nrPost: NRPost
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var forceAutoload: Bool
    private var fullWidth: Bool
    private var theme: Theme
    @State private var name: String
    @EnvironmentObject private var parentDIM: DIMENSIONS
    @State private var couldBeImposter: Int16
    
    init(nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.fullWidth = fullWidth
        self.theme = theme
        self.name = nrPost.anyName
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
    }
    
    var body: some View {
        if postRowDeletableAttributes.blocked {
            HStack {
                Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
            )
            .hCentered()
        }
        else {
            VStack(alignment: .leading) {
                HStack(alignment: .top) { // name + reply + context menu
                    VStack(alignment: .leading) { // Name + menu "replying to"
                        HStack(spacing: 5) {
                            // profile image
                            PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 20, forceFlat: nrPost.isScreenshot)
                                .onTapGesture(perform: navigateToContact)
                            
                            Text(name) // Name
                                .animation(.easeIn, value: name)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .fontWeightBold()
                                .lineLimit(1)
                                .onTapGesture(perform: navigateToContact)
                                .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
                                    guard profile.pubkey == nrPost.pubkey else { return }
                                    withAnimation {
                                        name = profile.name
                                    }
                                }
                            
                            if couldBeImposter == 1 {
                                PossibleImposterLabel(possibleImposterPubkey: nrPost.pubkey, followingPubkey: nrPost.contact?.similarToPubkey)
                            }
                            
                            Group {
                                Text(verbatim: " ·") //
                                Ago(nrPost.createdAt)
                                    .equatable()
                                if let via = nrPost.via {
                                    Text(" · via \(via)") //
                                        .lineLimit(1)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        }
                        ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                    }
                    
                    Spacer()
                }
//                .frame(height: 40)
                VStack(alignment: .leading) {
//                    Color.green
//                        .frame(height: 50)
//                        .debugDimensions("QuotedNoteFrVi.availableWidth \(parentDIM.listWidth)", alignment: .topLeading)
                    NoteTextRenderView(nrPost: nrPost, fullWidth: fullWidth, forceAutoload: forceAutoload, theme: theme)
//                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: parentDIM.listWidth - 20, isScreenshot: nrPost.isScreenshot))
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 5)
            .background(
                theme.background
                    .cornerRadius(8)
                    .onTapGesture(perform: navigateToPost)
            )
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(theme.lineColor.opacity(0.5), lineWidth: 1)
//            )
            .onAppear {
                if (nrPost.contact == nil) || (nrPost.contact?.metadata_created_at == 0) {
                    L.og.debug("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(nrPost.pubkey)")
                    bg().perform {
                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.onAppear")
                        QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                    }
                }
            }
            .onDisappear {
                if (nrPost.contact == nil) || (nrPost.contact?.metadata_created_at == 0) {
                    bg().perform {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
                }
            }
            .task {
                guard let nrContact = nrPost.contact else { return }
                guard !SettingsStore.shared.lowDataMode else { return }
                guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                guard nrContact.metadata_created_at != 0 else { return }
                guard nrContact.couldBeImposter == -1 else { return }
                
                guard let la = NRState.shared.loggedInAccount else { return }
                guard la.account.publicKey != nrContact.pubkey else { return }
                guard !la.isFollowing(pubkey: nrContact.pubkey) else { return }
                
                guard !NewOnboardingTracker.shared.isOnboarding else { return }
                guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }

                let contactAnyName = nrContact.anyName.lowercased()
                let currentAccountPubkey = NRState.shared.activeAccountPublicKey
                let cPubkey = nrContact.pubkey

                bg().perform { [weak nrContact] in
                    guard let nrContact else { return }
                    guard let account = account() else { return }
                    guard account.publicKey == currentAccountPubkey else { return }
                    guard let (_, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                        pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                    }) else { return }
                    
                    guard let cPic = nrContact.pictureUrl, similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                    Task.detached(priority: .background) {
                        let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                        DispatchQueue.main.async { [weak nrContact] in
                            guard let nrContact else { return }
                            guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                            couldBeImposter = similarPFP ? 1 : 0
                            nrContact.couldBeImposter = couldBeImposter
                            bg().perform {
                                guard currentAccountPubkey == Nostur.account()?.publicKey else { return }
                                nrContact.contact?.couldBeImposter = similarPFP ? 1 : 0
    //                            DataProvider.shared().bgSave()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func navigateToContact() {
        if let nrContact = nrPost.contact {
            navigateTo(nrContact)
        }
        else {
            navigateTo(ContactPath(key: nrPost.pubkey))
        }
    }    
    private func navigateToPost() {
        navigateTo(nrPost)
    }
}

struct QuotedNoteFragmentView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            PreviewFeed {
                // Mention at #[5]
                if let event0 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe") {
                    Box {
                        PostRowDeletable(nrPost: event0)
                    }
                }
                
                
                if let event1 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                    Box {
                        QuotedNoteFragmentView(nrPost: event1, theme: Themes.default.theme)
                    }
                }
                
                if let event2 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                    Box {
                        QuotedNoteFragmentView(nrPost: event2, theme: Themes.default.theme)
                    }
                }
            }
        }
    }
}
