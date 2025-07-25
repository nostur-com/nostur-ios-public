////
////  ProfileOverlayCard.swift
////  Nostur
////
////  Created by Fabian Lachman on 08/07/2023.
////
//
//import SwiftUI
//import Combine
//import NostrEssentials
//
//struct ProfileOverlayCardContainer: View {
//    let pubkey: String
//    @State var contact: NRContact? = nil
//    var zapEtag: String? = nil // so other clients can still tally zaps
//    
//    @State private var backlog = Backlog(timeout: 15, auto: true)
//    @State private var error: String? = nil
//    
//    var body: some View {
//        VStack {
//            if let error {
//                Text(error)
//            }
//            else if let contact {
//                ProfileOverlayCard(contact: contact, zapEtag: zapEtag)
//            }
//            else {
//                ProgressView()
//                    .onAppear {
//                        if let cachedNRContact = NRContactCache.shared.retrieveObject(at: pubkey) {
//                            self.contact = cachedNRContact
//                            return
//                        }
//                        bg().perform {
//                            if let nrContact = NRContact.fetch(pubkey) {
//                                DispatchQueue.main.async {
//                                    self.contact = nrContact
//                                }
//                            }
//                            else {
//                                let reqTask = ReqTask(
//                                    prio: true,
//                                    prefix: "CONTACT-",
//                                    reqCommand: { taskId in
//                                        nxReq(Filters(authors: [pubkey], kinds: [0], limit: 1), subscriptionId: taskId)
//                                    },
//                                    processResponseCommand: { taskId, _, _ in
//                                        bg().perform {
//                                            if let nrContact = NRContact.fetch(pubkey) {
//                                                DispatchQueue.main.async {
//                                                    self.contact = nrContact
//                                                }
//                                                self.backlog.clear()
//                                            }
//                                        }
//                                    },
//                                    timeoutCommand: { taskId in
//                                        DispatchQueue.main.async {
//                                            self.error = "Could not fetch contact info"
//                                        }
//                                    })
//                                
//                                backlog.add(reqTask)
//                                reqTask.fetch()
//                            }
//                        }
//                    }
//            }
//        }
//    }
//}
//
//struct ProfileOverlayCard: View {
//    @ObservedObject public var contact: NRContact
//    public var zapEtag: String? // so other clients can still tally zaps
//    public var withoutFollowButton = false
//    
//    @Environment(\.dismiss) private var dismiss
//    @Environment(\.theme) private var theme
//    @EnvironmentObject private var dim: DIMENSIONS
//    @ObservedObject private var fg: FollowingGuardian = .shared
//    @ObservedObject private var npn: NewPostNotifier = .shared
//    
//    @State private var backlog = Backlog(timeout: 5.0, auto: true)
//    @State private var lastSeen: String? = nil
//    @State private var isFollowingYou = false
//    @State private var fixedPfp: URL?
//    @State private var npub = ""
//    
//    static let grey = Color.init(red: 113/255, green: 118/255, blue: 123/255)
//    
//    private var hasFixedName: Bool {
//        if let fixedName = contact.fixedName, fixedName != contact.anyName {
//            return true
//        }
//        return false
//    }
//    
//    private var hasNip05Shortened: Bool {
//        guard contact.nip05 != nil, contact.nip05verified else { return false }
//        if contact.nip05nameOnly.lowercased() == contact.anyName.lowercased() {
//            return true
//        }
//        if contact.nip05nameOnly.lowercased() == "_" {
//            return true
//        }
//        if contact.nip05nameOnly.lowercased() == "" {
//            return true
//        }
//        return false
//    }
//    
//    var body: some View {
//        Box(showGutter: false) {
//            VStack(alignment: .leading) {
//                HStack(alignment: .top) {
//                    ZappablePFP(pubkey: contact.pubkey, contact: contact, size: 75.0, zapEtag: zapEtag)
//                        .onTapGesture {
//                            dismiss()
//                            navigateTo(contact)
//                            sendNotification(.dismissMiniProfile)
//                        }
//                        .overlay(alignment: .bottomTrailing) {
//                            if let fixedPfp {
//                                FixedPFP(picture: fixedPfp)
//                            }
//                        }
//                    
//                    Spacer()
//                    
//                    VStack(alignment: .trailing) {
//                        HStack {
//                            if contact.anyLud {
//                                ProfileZapButton(contact: contact, zapEtag: zapEtag)
//                            }
//                            if (!withoutFollowButton) {
//                                FollowButton(pubkey: contact.pubkey)
//                            }
//                        }
//                        HStack {
//                            Button {
//                                NewPostNotifier.shared.toggle(contact.pubkey)
//                            } label: {
//                                Image(systemName: "bell")
//                                    .resizable()
//                                    .frame(width: 20, height: 20)
//                                    .foregroundColor(theme.primary)
//                                    .overlay(alignment: .topTrailing) {
//                                        Image(systemName: npn.enabledPubkeys.contains(contact.pubkey) ? "checkmark.circle.fill" : "plus")
//                                            .resizable()
//                                            .frame(width: 8, height: 8)
//                                            .foregroundColor(npn.enabledPubkeys.contains(contact.pubkey) ? .green : theme.primary)
//                                            .padding(1)
//                                            .background(theme.listBackground)
//                                            .offset(y: -4)
//                                    }
//                            }
//                            .padding(.trailing, 10)
//                            
//                            if account()?.isFullAccount ?? false {
//                                Button {
//                                    UserDefaults.standard.setValue("Messages", forKey: "selected_tab")
//                                    sendNotification(.dismissMiniProfile)
//                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
//                                        sendNotification(.triggerDM, (contact.pubkey, contact))
//                                    }
//                                } label: { Image(systemName: "envelope.fill") }
//                                .buttonStyle(NosturButton())
//                            }
//                            
//                            Button("Show feed") {
//                                dismiss()
//                                UserDefaults.standard.setValue("Main", forKey: "selected_tab")
//                                sendNotification(.clearNavigation)
//                                sendNotification(.showingSomeoneElsesFeed, contact)
//                                sendNotification(.dismissMiniProfile)
//                            }
//                            .buttonStyle(NosturButton())
//                        }
//                    }
//                }
//                
//                VStack(alignment: .leading) {
//                    HStack(alignment: .bottom, spacing: 3) {
//                        Text(contact.anyName).font(.title).foregroundColor(.primary)
//                            .lineLimit(1)
//                        
//                        if contact.similarToPubkey == nil && hasNip05Shortened {
//                            NostrAddress(nip05: contact.nip05 ?? "", shortened: true)
//                                .layoutPriority(3)
//                                .offset(y: -4)
//                        }
//
//                        Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 7)
//                            .padding(.vertical, 2)
//                            .background(Color.secondary)
//                            .opacity(0.7)
//                            .cornerRadius(13)
//                            .offset(y: -4)
//                            .opacity(isFollowingYou ? 1.0 : 0)
//                    }
//                    
//                    CopyableTextView(text: npub)
//                        .lineLimit(1)
//                        .frame(width: 140, alignment: .leading)
//                    
//                    Color.clear
//                        .frame(height: 15)
//                        .overlay(alignment: .leading) {
//                            NewPossibleImposterLabel(nrContact: contact)
//                            if contact.similarToPubkey == nil, let nip05 = contact.nip05, contact.nip05verified, contact.nip05nameOnly.lowercased() != contact.anyName.lowercased(), !hasNip05Shortened {
//                                NostrAddress(nip05: nip05, shortened: false)
//                                    .layoutPriority(3)
//                            }
//                        }
//                    
//                    HStack {
//                        Text("Previously known as: \(contact.fixedName ?? "")").font(.caption).foregroundColor(.primary)
//                            .lineLimit(1)
//                        Image(systemName: "multiply.circle.fill")
//                            .onTapGesture {
//                                contact.setFixedName(contact.anyName)
//                            }
//                    }
//                    .opacity(hasFixedName ? 1.0 : 0)
//                    
//                    Text(verbatim: lastSeen ?? "Last seen:")
//                        .font(.caption)
//                        .foregroundColor(.primary)
//                        .lineLimit(1)
//                        .opacity(lastSeen != nil ? 1.0 : 0)
//                        .animation(.easeIn, value: lastSeen)
//                }
//                .contentShape(Rectangle())
//                .onTapGesture {
//                    dismiss()
//                    navigateTo(contact)
//                    sendNotification(.dismissMiniProfile)
//                }
//                .padding(.bottom, 10)
//                .offset(y: -15.0)
//                
//                ScrollView {
//                    NRTextDynamic("\(String(contact.about ?? ""))\n")
//                }
//                    .frame(maxHeight: 65.0)
//                
//                FollowedBy(pubkey: contact.pubkey)
//                    .frame(minHeight: 95.0)
//                
//                HStack(spacing:0) {
//                    Button(String(localized:"Posts", comment:"Tab title")) {
//                        dismiss()
//                        navigateTo(contact)
//                        sendNotification(.dismissMiniProfile)
//                    }
//                    Spacer()
//                    Button(String(localized:"Following", comment:"Tab title")) {
//                        dismiss()
//                        navigateTo(NRContactPath(nrContact: contact, tab:"Following"))
//                        sendNotification(.dismissMiniProfile)
//                    }
//                    Spacer()
//                    Button(String(localized:"Media", comment:"Tab title")) {
//                        dismiss()
//                        navigateTo(NRContactPath(nrContact: contact, tab:"Media"))
//                        sendNotification(.dismissMiniProfile)
//                    }
//                    Spacer()
//                    Button(String(localized:"Reactions", comment:"Tab title")) {
//                        dismiss()
//                        navigateTo(NRContactPath(nrContact: contact, tab:"Reactions"))
//                        sendNotification(.dismissMiniProfile)
//                    }
//                    Spacer()
//                    Button(String(localized:"Zaps", comment:"Tab title")) {
//                        dismiss()
//                        navigateTo(NRContactPath(nrContact: contact, tab:"Zaps"))
//                        sendNotification(.dismissMiniProfile)
//                    }
//                }
//                .padding(.top, 10)
////                .background(theme.listBackground)
//            }
//        }
//        .padding(10)
//        .background {
//            theme.listBackground
//                .shadow(color: Color("ShadowColor").opacity(0.25), radius: 5)
//        }
//        .onChange(of: contact.pictureUrl) { newPictureUrl in
//            guard let oldFixedPfp = contact.fixedPfp,
//                  oldFixedPfp != newPictureUrl?.absoluteString,
//                  let fixedPfpUrl = URL(string: oldFixedPfp),
//                  hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
//            else { return }
//            DispatchQueue.main.async {
//                withAnimation {
//                    self.fixedPfp = fixedPfpUrl
//                }
//            }
//        }
//        .task { [weak contact] in
//            guard let contact else { return }
//            
//            bg().perform {
//                if let fixedPfp = contact.fixedPfp,
//                   fixedPfp != contact.contact?.picture,
//                   let fixedPfpUrl = URL(string: fixedPfp),
//                   hasFPFcacheFor(pfpImageRequestFor(fixedPfpUrl))
//                {
//                    DispatchQueue.main.async {
//                        withAnimation {
//                            self.fixedPfp = fixedPfpUrl
//                        }
//                    }
//                }
//            }
//        }
//        .task { [weak contact, weak backlog] in
//            guard let nrContact = contact else { return }
//            let contact = nrContact.contact
//            
//            bg().perform { [weak contact] in
//                guard let contact, let backlog else { return }
//                
//                let npub = contact.npub
//                let isFollowingYou = contact.followsYou()
//                
//                EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "ProfileOverlayCard")
//                
//                DispatchQueue.main.async {
//                    withAnimation {
//                        self.npub = npub
//                        if (isFollowingYou) {
//                            self.isFollowingYou = true
//                        }
//                    }
//                }
//                
//                let task = ReqTask(
//                    reqCommand: { (taskId) in
//                        req(RM.getUserProfileKinds(pubkey: contact.pubkey, subscriptionId: taskId, kinds: [0,3]))
//                    },
//                    processResponseCommand: { [weak contact] (taskId, _, _) in
//                        bg().perform {
//                            guard let contact else { return }
//                            if (contact.followsYou()) {
//                                DispatchQueue.main.async {
//                                    self.isFollowingYou = true
//                                }
//                            }
//                        }
//                    },
//                    timeoutCommand: { [weak contact] taskId in
//                        bg().perform {
//                            guard let contact else { return }
//                            if (contact.followsYou()) {
//                                DispatchQueue.main.async {
//                                    self.isFollowingYou = true
//                                }
//                            }
//                        }
//                    })
//
//                backlog.add(task)
//                task.fetch()
//                
//                if (NIP05Verifier.shouldVerify(contact)) {
//                    NIP05Verifier.shared.verify(contact)
//                }
//             
//                guard contact.anyLud else { return }
//                let lud16orNil = contact.lud16
//                let lud06orNil = contact.lud06
//                Task { [weak contact] in
//                    do {
//                        if let lud16 = lud16orNil, lud16 != "" {
//                            let response = try await LUD16.getCallbackUrl(lud16: lud16)
//                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
//                                await bg().perform {
//                                    guard let contact else { return }
//                                    contact.zapperPubkeys.insert(zapperPubkey)
//#if DEBUG
//                                    L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
//#endif
//                                }
//                            }
//                        }
//                        else if let lud06 = lud06orNil, lud06 != "" {
//                            let response = try await LUD16.getCallbackUrl(lud06: lud06)
//                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
//                                await bg().perform {
//                                    guard let contact else { return }
//                                    contact.zapperPubkeys.insert(zapperPubkey)
//#if DEBUG
//                                    L.og.info("⚡️ contact.zapperPubkey updated: \(zapperPubkey)")
//#endif
//                                }
//                            }
//                        }
//                    }
//                    catch {
//#if DEBUG
//                        L.og.error("⚡️ problem in lnurlp \(error)")
//#endif
//                    }
//                }
//            }
//        }
//        .onChange(of: contact.nip05) { [weak contact] _ in
//            bg().perform {
//                guard let contact = contact?.contact else { return }
//                if (NIP05Verifier.shouldVerify(contact)) {
//                    NIP05Verifier.shared.verify(contact)
//                }
//            }
//        }
//        .task { [weak contact, weak backlog] in
//            guard let contact, let backlog else { return }
//            let contactPubkey = contact.pubkey
//            // Note: can't use prio queue here, because if multiple relays respond and the first one has older data, SEEN will be incorrect.
//            let reqTask = ReqTask(prefix: "SEEN-", reqCommand: { taskId in
//                req(RM.getLastSeen(pubkey: contactPubkey, subscriptionId: taskId))
//            }, processResponseCommand: { taskId, _, _ in
//                bg().perform {
//                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
//                        let agoString = last.date.agoString
//                        DispatchQueue.main.async {
//                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
//                        }
//                    }
//                }
//            }, timeoutCommand: { taskId in
//                bg().perform {
//                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
//                        let agoString = last.date.agoString
//                        DispatchQueue.main.async {
//                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
//                        }
//                    }
//                }
//            })
//            
//            backlog.add(reqTask)
//            reqTask.fetch()
//        }
//        .onDisappear { [weak contact] in
//            bg().perform {
//                guard let contact else { return }
//                contact.contact?.zapState = nil
//            }
//        }
//    }
//}
//
//struct ProfileOverlayCard_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewContainer({ pe in pe.loadContacts() }) {
//            if let contact = PreviewFetcher.fetchNRContact() {
//                ProfileOverlayCard(contact: contact)
//            }
//        }
//        .background(Color.red)
//    }
//}
