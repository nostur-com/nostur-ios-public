//
//  SelectedParticipantView.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2024.
//

import SwiftUI

struct SelectedParticipantView: View {
    @Environment(\.dismiss) private var dismiss
    public var withoutFollowButton = false
    
    @EnvironmentObject private var themes: Themes
    @ObservedObject var nrContact: NRContact
    public let showZapButton: Bool
    @ObservedObject var liveEvent: NRLiveEvent
    public let showModeratorControls: Bool
    @Binding var selectedContact: NRContact?
    
    @EnvironmentObject private var npn: NewPostNotifier
    @ObservedObject private var fg: FollowingGuardian = .shared
    
    @State private var similarPFP = false
    @State private var similarToPubkey: String? = nil
    @State private var backlog = Backlog(timeout: 5.0, auto: true)
    @State private var lastSeen: String? = nil
    @State private var isFollowingYou = false
    @State private var fixedPfp: URL?
    @State private var npub = ""

    
    @State private var triggerStrike = false
    @State private var customAmount: Double? = nil
    @State private var zapMessage: String = ""
    @State private var isZapped = false
    
    var couldBeImposter: Bool {
        guard let account = account() else { return false }
        guard account.publicKey != nrContact.pubkey else { return false }
        guard !nrContact.following else { return false }
        guard nrContact.couldBeImposter == -1 else { return nrContact.couldBeImposter == 1 }
        return similarPFP
    }
    
    private var hasFixedName: Bool {
        if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
            return true
        }
        return false
    }
    
    private var hasNip05Shortened: Bool {
        guard nrContact.nip05 != nil, nrContact.nip05verified else { return false }
        if nrContact.nip05nameOnly.lowercased() == nrContact.anyName.lowercased() {
            return true
        }
        if nrContact.nip05nameOnly.lowercased() == "_" {
            return true
        }
        if nrContact.nip05nameOnly.lowercased() == "" {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                        .onReceive(receiveNotification(.sendCustomZap)) { notification in
                            // Complete custom zap
                            let customZap = notification.object as! CustomZap
                            guard customZap.customZapId == customZapId else { return }
                            customAmount = customZap.amount
                            zapMessage = customZap.publicNote
                            triggerStrike = true
                        }
                        .overlay {
                            if triggerStrike {
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            guard !isZapped else { return }
                                            guard let contact = nrContact.contact else { return }
                                            self.triggerZap(strikeLocation: geo.frame(in: .global).origin, contact: contact, zapMessage: zapMessage, amount: customAmount)
                                        }
                                }
                            }
                        }
                    
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                        navigateTo(nrContact)
                        selectedContact = nil
                    }
                    
                    Text(nrContact.anyName)
                        .fontWeightBold()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        
                     
                    if hasFixedName {
                        HStack {
                            Text("Previously known as: \(nrContact.fixedName ?? "")").font(.caption).foregroundColor(.primary)
                                .lineLimit(1)
                            Image(systemName: "multiply.circle.fill")
                                .onTapGesture {
                                    nrContact.setFixedName(nrContact.anyName)
                                }
                        }
                    }
                }
                
                Spacer()
                
                if npn.isEnabled(for: nrContact.pubkey) {
                    Image(systemName: "bell")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 10, height: 10)
                                .foregroundColor(.green)
                                .background(themes.theme.background)
                                .offset(y: -3)
                        }
                        .offset(y: 3)
                        .onTapGesture { npn.toggle(nrContact.pubkey) }
                        .padding(.trailing, 10)
                        .padding(.top, 5)
                }
                else {
                    Image(systemName: "bell")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "plus")
                                .resizable()
                                .frame(width: 10, height: 10)
                                .background(themes.theme.background)
                                .border(themes.theme.background, width: 2.0)
                                .offset(y: -3)
                        }
                        .offset(y: 3)
                        .onTapGesture { npn.toggle(nrContact.pubkey) }
                        .padding(.trailing, 10)
                        .padding(.top, 5)
                }
                
                VStack {
                    Button {
                        guard isFullAccount() else { showReadOnlyMessage(); return }
                        if (nrContact.following && !nrContact.privateFollow) {
                            nrContact.follow(privateFollow: true)
                        }
                        else if (nrContact.following && nrContact.privateFollow) {
                            nrContact.unfollow()
                        }
                        else {
                            nrContact.follow()
                        }
                    } label: {
                        FollowButton(isFollowing: nrContact.following, isPrivateFollowing: nrContact.privateFollow)
                    }
                    .disabled(!fg.didReceiveContactListThisSession)
                    
                    if showZapButton {
                        Button {
                            self.sendSats()
                        } label: {
                            Text("\(Image(systemName: "bolt.fill")) Send sats")
                                .frame(width: 84)
                        }
                        .buttonStyle(NosturButton())
                    }
                }
            }
            .border(Color.red)
            
            CopyableTextView(text: npub)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .border(Color.red)
            
            if !couldBeImposter && hasNip05Shortened {
                NostrAddress(nip05: nrContact.nip05 ?? "", shortened: true)
                    .layoutPriority(3)
//                    .offset(y: -4)
            }
            
            Color.clear
                .frame(height: 15)
                .border(Color.red)
                .overlay(alignment: .leading) {
                    if couldBeImposter {
                        PossibleImposterLabel(possibleImposterPubkey: nrContact.pubkey, followingPubkey: similarToPubkey ?? nrContact.similarToPubkey)
                    }
                    else if let nip05 = nrContact.nip05, nrContact.nip05verified, nrContact.nip05nameOnly.lowercased() != nrContact.anyName.lowercased(), !hasNip05Shortened {
                        NostrAddress(nip05: nip05, shortened: false)
                            .layoutPriority(3)
                    }
                }
                .border(Color.red)
            
//            FollowedBy(pubkey: nrContact.pubkey)
//                .frame(minHeight: 65.0)
//                .border(Color.red)
            
            Spacer()
            
            // Moderator actions
            if showModeratorControls {
                HStack(alignment: .top) {

                    if liveEvent.pubkeysOnStage.contains(nrContact.pubkey) {
                        VStack {
                            Button("Remove from stage", systemImage: "mic.fill.badge.xmark") {
                                guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
                                    return
                                }
                                Task { @MainActor in
                                    try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, canPublish: false)
                                }
                                dismiss()
                            }
                            .font(.title2)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NestButtonStyle(theme: themes.theme, style: .borderedProminent))
                            
                            Text("Remove from stage")
                                .font(.caption)
                        }
                    }
                    else {
                        VStack {
                            Button("Add to stage", systemImage: "mic.fill.badge.plus") {
                                guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
                                    return
                                }
                                Task { @MainActor in
                                    try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, canPublish: true)
                                }
                                dismiss()
                            }
                            .font(.title2)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NestButtonStyle(theme: themes.theme, style: .borderedProminent))
                            
                            Text("Add to stage")
                                .font(.caption)
                        }
                    }
                    
                    Spacer()
                    
                    if liveEvent.admins.contains(nrContact.pubkey) {
                        VStack {
                            Button("Remove moderator", systemImage: "person.slash.fill") {
                                guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
                                    return
                                }
                                Task { @MainActor in
                                    try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, isAdmin: false)
                                }
                                dismiss()
                                
                            }
                            .font(.title2)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NestButtonStyle(theme: themes.theme, style: .borderedProminent))
                            
                            Text("Remove moderator")
                                .font(.caption)
                        }
                    }
                    else {
                        VStack {
                            Button("Make moderator", systemImage: "arrow.up.and.person.rectangle.portrait") {
                                guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
                                    return
                                }
                                Task { @MainActor in
                                    try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, isAdmin: true)
                                }
                                dismiss()
                            }
                            .font(.title2)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NestButtonStyle(theme: themes.theme, style: .borderedProminent))
                            
                            Text("Make moderator")
                                .font(.caption)
                        }
                    }
                }
                    .padding(10)
            }
        }
//        .navigationTitle(nrContact.anyName)
//        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: nrContact.pictureUrl) { newPictureUrl in
            guard let oldFixedPfp = nrContact.fixedPfp,
                  oldFixedPfp != newPictureUrl?.absoluteString,
                  let fixedPfpUrl = URL(string: oldFixedPfp),
                  hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl, size: 20.0))
            else { return }
            DispatchQueue.main.async {
                withAnimation {
                    self.fixedPfp = fixedPfpUrl
                }
            }
        }
        .task {
            bg().perform {
                if let fixedPfp = nrContact.fixedPfp,
                   fixedPfp != nrContact.contact?.picture,
                   let fixedPfpUrl = URL(string: fixedPfp),
                   hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl, size: 20.0))
                {
                    DispatchQueue.main.async {
                        withAnimation {
                            self.fixedPfp = fixedPfpUrl
                        }
                    }
                }
            }
            
            guard !SettingsStore.shared.lowDataMode else { return }
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            guard !nrContact.following else { return }
            guard nrContact.metadata_created_at != 0 else { return }
            guard nrContact.couldBeImposter == -1 else { return }
            guard let cPic = nrContact.pictureUrl else { return }
            guard !NewOnboardingTracker.shared.isOnboarding else { return }
            guard let followingCache = NRState.shared.loggedInAccount?.followingCache else { return }
            
            let contactAnyName = nrContact.anyName.lowercased()
            let cPubkey = nrContact.pubkey
            let currentAccountPubkey = NRState.shared.activeAccountPublicKey
            
            bg().perform {
                guard let account = account() else { return }
                guard account.publicKey == currentAccountPubkey else { return }
                guard let (followingPubkey, similarFollow) = followingCache.first(where: { (pubkey: String, follow: FollowCache) in
                    pubkey != cPubkey && isSimilar(string1: follow.anyName.lowercased(), string2: contactAnyName)
                }) else { return }
                
                guard similarFollow.pfpURL != nil, let wotPic = similarFollow.pfpURL else { return }
                
                L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarFollow.anyName)")
                
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    if similarPFP {
                        L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                    }
                    
                    DispatchQueue.main.async {
                        guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                        self.similarPFP = similarPFP
                        self.similarToPubkey = followingPubkey
                        nrContact.couldBeImposter = similarPFP ? 1 : 0
                        nrContact.similarToPubkey = similarPFP ? followingPubkey : nil
                    }
                }
            }
        }
        .task { [weak backlog] in
            let contact = nrContact.contact
            
            bg().perform {
                guard let backlog, let contact else { return }
                
                let npub = contact.npub
                let isFollowingYou = contact.followsYou()
                
                EventRelationsQueue.shared.addAwaitingContact(contact)
                
                DispatchQueue.main.async {
                    self.npub = npub
                    withAnimation {
                        if (isFollowingYou) {
                            self.isFollowingYou = true
                        }
                    }
                }
                
                let task = ReqTask(
                    reqCommand: { (taskId) in
                        req(RM.getUserProfileKinds(pubkey: contact.pubkey, subscriptionId: taskId, kinds: [0,3]))
                    },
                    processResponseCommand: { [weak contact] (taskId, _, _) in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    self.isFollowingYou = true
                                }
                            }
                        }
                    },
                    timeoutCommand: { [weak contact] taskId in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    self.isFollowingYou = true
                                }
                            }
                        }
                    })

                backlog.add(task)
                task.fetch()
                
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
             
                guard contact.anyLud else { return }
                let lud16orNil = contact.lud16
                let lud06orNil = contact.lud06
                Task { [weak contact] in
                    do {
                        if let lud16 = lud16orNil, lud16 != "" {
                            let response = try await LUD16.getCallbackUrl(lud16: lud16)
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkey = response.nostrPubkey!
                                    L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                                }
                            }
                        }
                        else if let lud06 = lud06orNil, lud06 != "" {
                            let response = try await LUD16.getCallbackUrl(lud06: lud06)
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkey = response.nostrPubkey!
                                    L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                                }
                            }
                        }
                    }
                    catch {
                        L.og.error("problem in lnurlp \(error)")
                    }
                }
            }
        }
        .onChange(of: nrContact.nip05) { _ in
            bg().perform {
                guard let contact = nrContact.contact else { return }
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
            }
        }
    }
    
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var activeColor: Color? = nil
    @State private var customZapId: UUID? = nil
    @State private var isLoading = false
    
    private func sendSats() {
        guard isFullAccount() else { showReadOnlyMessage(); return }

        if ss.nwcReady {
            // Trigger custom zap
            customZapId = UUID()
            if let customZapId {
                sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: nrContact.anyName, customZapId: customZapId, zapAtag: liveEvent.id))
            }
        }
        else {
            nonNWCtap()
        }
    }
    
    private func nonNWCtap() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard nrContact.anyLud else { return }
        isLoading = true
        
        if let lud16 = nrContact.lud16 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 100000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrContact.zapperPubkey = response.nostrPubkey!
                            }
                            // Old zap sheet
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: nrContact.mainContact, zapAtag: liveEvent.id, withPending: true)
                            sendNotification(.showZapSheet, paymentInfo)
                            
                            //                            // Trigger custom zap
                            //                            customZapId = UUID()
                            //                            if let customZapId {
                            //                                sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(nrPost: nrPost!, customZapId: customZapId))
                            //                            }
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.og.error("🔴🔴 problem in lnurlp \(error)")
                }
            }
        }
        else if let lud06 = nrContact.lud06 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 200000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrContact.zapperPubkey = response.nostrPubkey!
                            }
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: nrContact.mainContact, zapAtag: liveEvent.id, withPending: true)
                            sendNotification(.showZapSheet, paymentInfo)
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.og.error("🔴🔴🔴🔴 problem in lnurlp \(error)")
                }
            }
        }
    }
    
    func triggerZap(strikeLocation: CGPoint, contact: Contact, zapMessage: String = "", amount: Double? = nil) {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard let account = account() else { return }
        let isNC = account.isNC
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        let selectedAmount = amount ?? ss.defaultZapAmount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            sendNotification(.lightningStrike, LightningStrike(location: strikeLocation, amount: selectedAmount))
            SoundManager.shared.playThunderzap()
            withAnimation(.easeIn(duration: 0.25).delay(0.25)) {// wait 0.25 for the strike
                activeColor = .yellow
            }
        }
        let cancellationId = UUID() // We dont cancel on nests (because already have full sheet confirmation), but still cancellation id until we refactor api
        isZapped = true
        
        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: nrContact.pubkey, aTag: liveEvent.id, zapState: .initiated))

        bg().perform {
            NWCRequestQueue.shared.ensureNWCconnection()
            let zap = Zap(isNC: isNC, amount: Int64(selectedAmount), contact: contact, aTag: liveEvent.id, cancellationId: cancellationId, zapMessage: zapMessage, withPending: true)
            NWCZapQueue.shared.sendZap(zap)
            Task { @MainActor in
                self.isZapped = false
                self.triggerStrike = false
                self.customAmount = nil
                self.zapMessage = ""
            }
        }
    }
 
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.parseMessages([
            ###"["EVENT","LIVE",{"content":"","created_at":1718076971,"id":"1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2","kind":30311,"pubkey":"8a0969377e9abfe215e99f02e1789437892526b1d1e0b1ca4ed7cbf88b1cc421","sig":"2eb76ceda6c1345465998fe14cf53da308880fd1cf2f70e6c0d6e248d1a903105301f99f04c8e230272aaf0c8ee5a35c7c2b03cc63e64e62e88b7b55111f3920","tags":[["d","1718063831277"],["title","Corny Chat News"],["summary","Weekly news roundup providing a summary of the weeks headlines and topical discussion regarding Nostr, Lightning, Bitcoin, Geopolitics and Clown World, Humor and more."],["image","https://image.nostr.build/ea30115d83b1d3c303095a0a3349514ca2a88e12b9c5dd7fd92e984502be55f0.jpg"],["service","https://cornychat.com/cornychatnews"],["streaming","https://cornychat.com/cornychatnews"],["starts","1718063831"],["ends","1718080571"],["status","live"],["current_participants","7"],["t","talk"],["t","talk show"],["L","com.cornychat"],["l","cornychat.com","com.cornychat"],["l","audiospace","com.cornychat"],["r","https://cornychat.com/cornychatnews"],["p","50809a53fef95904513a840d4082a92b45cd5f1b9e436d9d2b92a89ce091f164","","Participant"],["p","7cc328a08ddb2afdf9f9be77beff4c83489ff979721827d628a542f32a247c0e","","Participant"],["p","21b419102da8fc0ba90484aec934bf55b7abcf75eedb39124e8d75e491f41a5e","","Room Owner"],["p","52387c6b99cc42aac51916b08b7b51d2baddfc19f2ba08d82a48432849dbdfb2","","Participant"],["p","50de492cfe5472450df1a0176fdf6d915e97cb5d9f8d3eccef7d25ff0a8871de","","Speaker"],["p","9322bd922f20c6fcd9e913454727b3bbc2d096be4811971055a826dda3d4cb0b","","Participant"],["p","cc76679480a4504b963a3809cba60b458ebf068c62713621dda94b527860447d","","Participant"]]}]"###
        ])
    }) {
        if let contact = PreviewFetcher.fetchNRContact(), let liveEvent = PreviewFetcher.fetchEvent("1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2") {
            let nrLiveEvent = NRLiveEvent(event: liveEvent)
            VStack {
                SelectedParticipantView(nrContact: contact, showZapButton: false, liveEvent: nrLiveEvent, showModeratorControls: true, selectedContact: .constant(contact))
                    .padding(10)
                
                Divider()
                
                SelectedParticipantView(nrContact: contact, showZapButton: false, liveEvent: nrLiveEvent, showModeratorControls: false, selectedContact: .constant(contact))
                    .padding(10)
            }
        }
    }
}