////
////  Kind30311.swift
////  Nostur
////
////  Created by Fabian Lachman on 15/03/2025.
////
//
//import SwiftUI
//import NostrEssentials
//import NavigationBackport
//import SwiftUIFlow
//
//// TODO: finish this
//struct Kind30311: View {
//    @EnvironmentObject private var dim: DIMENSIONS
//    @Environment(\.theme) private var theme
//    @ObservedObject private var settings: SettingsStore = .shared
//    @ObservedObject private var nrPost: NRPost
//    @ObservedObject private var liveEvent: NRLiveEvent
//    
//    public var liveKitVoiceSession: LiveKitVoiceSession?
//    
//    private let hideFooter: Bool // For rendering in NewReply
//    private let isDetail: Bool
//    private let isEmbedded: Bool
//    private let fullWidth: Bool
//    private let forceAutoload: Bool
//    @State private var didStart = false
//    @State private var roomAddress: String? = nil
//    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: 3)
//    
//    private var availableWidth: CGFloat {
//        if isDetail || fullWidth || isEmbedded {
//            return dim.listWidth - 20
//        }
//        
//        return dim.availableNoteRowImageWidth()
//    }
//    
//    private var shouldAutoload: Bool {
//        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(liveEvent))
//    }
//
//    init(nrPost: NRPost, nrLiveEvent: NRLiveEvent, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool = false, hideFooter: Bool = false,  forceAutoload: Bool = false) {
//        self.liveEvent = nrLiveEvent
//        self.nrPost = nrPost
//        self.isDetail = isDetail
//        self.isEmbedded = isEmbedded
//        self.fullWidth = fullWidth
//        self.hideFooter = hideFooter
//        self.forceAutoload = forceAutoload
//    }
//    
//    var body: some View {
//        if isEmbedded {
//            self.embeddedView
//        }
//        else {
//            self.normalView
//        }
//    }
//    
//    @ViewBuilder
//    private var embeddedView: some View {
//        PostEmbeddedLayout(nrPost: nrPost) {
//            VStack(alignment: .leading, spacing: 0) {
//                VStack {
//                    headerView
//                    
//                    LazyVGrid(columns: gridColumns, spacing: 8.0) {
//                        ForEach(liveEvent.onStage.indices, id: \.self) { index in
//                            NestParticipantView(nrContact: liveEvent.onStage[index],
//                                                role: liveEvent.role(forPubkey: liveEvent.onStage[index].pubkey),
//                                                aTag: liveEvent.id,
//                                                disableZaps: true
//                            )
//                            .id(liveEvent.onStage[index].pubkey)
//                        }
//                    }
//                    
//                    Divider()
//                    
//                    LazyVGrid(columns: gridColumns, spacing: 8.0) {
//                        ForEach(liveEvent.listeners.indices, id: \.self) { index in
//                            NestParticipantView(nrContact: liveEvent.listeners[index],
//                                                role: liveEvent.role(forPubkey: liveEvent.listeners[index].pubkey),
//                                                aTag: liveEvent.id,
//                                                disableZaps: true
//                            )
//                            .id(liveEvent.listeners[index].pubkey)
//                        }
//                    }
//                }
//                
//                if let image = liveEvent.thumbUrl {
//                    MediaContentView(
//                        media: MediaContent(
//                            url: image
//                        ),
//                        availableWidth: dim.listWidth,
//                        placeholderHeight: dim.listWidth * 9/16,
//                        maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
//                        contentMode: .fill,
//                        upscale: true,
//                        autoload: shouldAutoload
//                    )
//                    .padding(.vertical, 10)
//                }
//            }
//            .onAppear {
//                liveEvent.fetchPresenceFromRelays()
//            }
//            .contentShape(Rectangle())
//            .onTapGesture {
//                UserDefaults.standard.setValue("Main", forKey: "selected_tab")
//                if IS_CATALYST || IS_IPAD {
//                    navigateTo(liveEvent)
//                }
//                else {
//                    // LOAD NEST
//                    if liveEvent.isLiveKit {
//                        LiveKitVoiceSession.shared.activeNest = liveEvent
//                    }
//                    // ALREADY PLAYING IN .OVERLAY, TOGGLE TO .DETAILSTREAM
//                    else if AnyPlayerModel.shared.nrLiveEvent?.id == liveEvent.id {
//                        AnyPlayerModel.shared.viewMode = .detailstream
//                    }
//                    // LOAD NEW .DETAILSTREAM
//                    else {
//                        Task {
//                            await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: liveEvent, availableViewModes: [.detailstream, .overlay])
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    
//    // TODO: Somehow get the width somewhere on parent views
//    @State private var vc: ViewingContext?
//    @State private var selectedContact: NRContact? = nil
//    @State private var account: CloudAccount? = nil
//    private var showModeratorControls: Bool {
//        if liveKitVoiceSession?.listenAnonymously ?? true { return false }
//        guard let account else { return false }
//        return liveEvent.admins.contains(account.publicKey) || liveEvent.pubkey == account.publicKey
//    }
//    
//    // Zap sheet NON-NWC
//    @State private var paymentInfo: PaymentInfo? = nil // NON-NWC ZAP
//    @State private var showNonNWCZapSheet = false // NON-NWC ZAP
//    
//    // Zap sheet NWC
//    @State private var zapCustomizerSheetInfo: ZapCustomizerSheetInfo? = nil // NWC ZAP
//    @State private var showZapSheet = false // NWC ZAP
//    
//    @ViewBuilder
//    var normalView: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
//            GeometryReader { geo in
//                ScrollView {
//                    VStack(spacing: 0) {
//                        if let vc, let liveKitVoiceSession {
//                            VStack {
//                                headerView
//                                
//                                participantsView
//                                    .onReceive(receiveNotification(.showZapCustomizerSheet)) { notification in
//                                        let zapCustomizerSheetInfo = notification.object as! ZapCustomizerSheetInfo
//                                        guard zapCustomizerSheetInfo.zapAtag != nil else { return }
//                                        self.showZapSheet = true
//                                        self.zapCustomizerSheetInfo = zapCustomizerSheetInfo
//                                    }
//                                    .onReceive(receiveNotification(.showZapSheet)) { notification in
//                                        let paymentInfo = notification.object as! PaymentInfo
//                                        guard paymentInfo.zapAtag != nil else { return }
//                                        self.paymentInfo = paymentInfo
//                                        self.showNonNWCZapSheet = true
//                                    }
//                                
//                                videoStreamView
//                                    .background(theme.background)
//                            }
//                            .onTapGesture {
//                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
//                                                                to: nil, from: nil, for: nil)
//                            }
//                            .overlay(alignment: .topTrailing) {
//                                if showModeratorControls {
//                                    self.recordingsMenu
//                                }
//                            }
//                            
//                            ChatRoom(aTag: liveEvent.id, anonymous: liveKitVoiceSession.listenAnonymously, chatVM: liveEvent.chatVM)
//                                .padding(.horizontal, 10)
//                                .environmentObject(vc)
//                        }
//                    }
//                    .frame(minHeight: geo.size.height)
//                }
//            }
//            .safeAreaInset(edge: .bottom) {
//                VStack {
//                    nestButtonsView
//                        .padding(10)
//                        .layoutPriority(1)
//                }
//                .background(theme.background)
//            }
//            .onAppear {
//                if let relaysTag = liveEvent.nEvent.fastTags.first(where: { $0.0 == "relays" }) {
//                    var relays: [String] = [normalizeRelayUrl(relaysTag.1)]
//                    if let relay = relaysTag.2 {
//                        relays = relays + [normalizeRelayUrl(relay)]
//                    }
//                    if let relay = relaysTag.3 {
//                        relays = relays + [normalizeRelayUrl(relay)]
//                    }
//                    if let relay = relaysTag.4 {
//                        relays = relays + [normalizeRelayUrl(relay)]
//                    }
//                    
//                    if let bech32 = try? ShareableIdentifier(prefix: "naddr", kind: 30311, pubkey: liveEvent.pubkey, dTag: liveEvent.dTag, relays: relays).bech32string {
//                        roomAddress = bech32
//                    }
//                }
//                
//                vc = ViewingContext(availableWidth: dim.articleRowImageWidth(), fullWidthImages: false, viewType: .row)
//                liveEvent.fetchPresenceFromRelays()
//                if let liveKitVoiceSession, liveEvent.liveKitConnectUrl != nil && !liveKitVoiceSession.listenAnonymously {
//                    account = Nostur.account()
//                }
//            }
//            .background(theme.background)
//            .preference(key: TabTitlePreferenceKey.self, value: liveEvent.title ?? "(Stream)")
//            .withNavigationDestinations()
//            .nbNavigationDestination(isPresented: $showZapSheet, destination: {
//                if let zapCustomizerSheetInfo {
//                    ZapCustomizerSheet(name: zapCustomizerSheetInfo.name, customZapId: zapCustomizerSheetInfo.customZapId, supportsZap: true)
//                        .environmentObject(NRState.shared)
//                        .presentationDetentsLarge()
//                        .environment(\.theme, theme)
//                        .presentationBackgroundCompat(theme.listBackground)
//                }
//            })
//            .nbNavigationDestination(isPresented: $showNonNWCZapSheet, destination: {
//                if let paymentInfo {
//                    PaymentAmountSelector(paymentInfo: paymentInfo)
//                        .environmentObject(NRState.shared)
//                        .presentationDetentsLarge()
//                        .environment(\.theme, theme)
//                        .presentationBackgroundCompat(theme.listBackground)
//                }
//            })
//            .sheet(item: $selectedContact) { nrContact in
//                NBNavigationStack {
//                    VStack {
//                        SelectedParticipantView(nrContact: nrContact, showZapButton: !(liveKitVoiceSession?.listenAnonymously ?? true), aTag: liveEvent.id, showModeratorControls: showModeratorControls, selectedContact: $selectedContact)
//                        
//                        Spacer()
//                        
//                        // Moderator actions
//                        if showModeratorControls {
//                            HStack(alignment: .top) {
//
//                                if liveEvent.pubkeysOnStage.contains(nrContact.pubkey) {
//                                    VStack {
//                                        Button("Remove from stage", systemImage: "mic.fill.badge.xmark") {
//                                            guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
//                                                return
//                                            }
//                                            Task { @MainActor in
//                                                try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, canPublish: false)
//                                            }
//                                            selectedContact = nil
//                                        }
//                                        .font(.title2)
//                                        .labelStyle(.iconOnly)
//                                        .buttonStyle(NestButtonStyle(theme: theme, style: .borderedProminent))
//                                        
//                                        Text("Remove from stage")
//                                            .font(.caption)
//                                    }
//                                }
//                                else {
//                                    VStack {
//                                        Button("Add to stage", systemImage: "mic.fill.badge.plus") {
//                                            guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
//                                                return
//                                            }
//                                            Task { @MainActor in
//                                                try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, canPublish: true)
//                                            }
//                                            selectedContact = nil
//                                        }
//                                        .font(.title2)
//                                        .labelStyle(.iconOnly)
//                                        .buttonStyle(NestButtonStyle(theme: theme, style: .borderedProminent))
//                                        
//                                        Text("Add to stage")
//                                            .font(.caption)
//                                    }
//                                }
//                                
//                                Spacer()
//                                
//                                if liveEvent.admins.contains(nrContact.pubkey) {
//                                    VStack {
//                                        Button("Remove moderator", systemImage: "person.slash.fill") {
//                                            guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
//                                                return
//                                            }
//                                            Task { @MainActor in
//                                                try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, isAdmin: false)
//                                            }
//                                            selectedContact = nil
//                                            
//                                        }
//                                        .font(.title2)
//                                        .labelStyle(.iconOnly)
//                                        .buttonStyle(NestButtonStyle(theme: theme, style: .borderedProminent))
//                                        
//                                        Text("Remove moderator")
//                                            .font(.caption)
//                                    }
//                                }
//                                else {
//                                    VStack {
//                                        Button("Make moderator", systemImage: "arrow.up.and.person.rectangle.portrait") {
//                                            guard case .account(let cloudAccount) = LiveKitVoiceSession.shared.accountType else {
//                                                return
//                                            }
//                                            Task { @MainActor in
//                                                try? await liveEvent.updatePermissions(account: cloudAccount, participantPubKey: nrContact.pubkey, isAdmin: true)
//                                            }
//                                            selectedContact = nil
//                                        }
//                                        .font(.title2)
//                                        .labelStyle(.iconOnly)
//                                        .buttonStyle(NestButtonStyle(theme: theme, style: .borderedProminent))
//                                        
//                                        Text("Make moderator")
//                                            .font(.caption)
//                                    }
//                                }
//                            }
//                                .padding(10)
//                        }
//                    }
//                    .environment(\.theme, theme)
//                    .padding(10)
//                    .toolbar {
//                        ToolbarItem(placement: .confirmationAction) {
//                            if IS_CATALYST {
//                                Button {
//                                    selectedContact = nil
//                                } label: {
//                                    Image(systemName: "xmark")
//                                       .imageScale(.large) // Adjust the size of the "X"
//                                }
//                            }
//                        }
//                    }
//                }
//                .nbUseNavigationStack(.never)
//                .presentationBackgroundCompat(theme.background)
//                .presentationDetents45ml()
//            }
//            .withLightningEffect()
//    }
//    
//
//    @ViewBuilder
//    private var headerView: some View {
//        if liveEvent.streamHasEnded {
//            HStack {
//                Text("Session has ended")
//                    .foregroundColor(.secondary)
//            }
//        }
//        else if liveEvent.totalParticipants > 0 || (liveKitVoiceSession?.isRecording ?? false) {
//            HStack {
//                if liveEvent.totalParticipants > 0 {
//                    if liveEvent.liveKitConnectUrl == nil {
//                        Text("\(liveEvent.totalParticipants) viewers")
//                            .foregroundColor(.secondary)
//                    }
//                    else {
//                        Text("\(liveEvent.totalParticipants) participants")
//                            .foregroundColor(.secondary)
//                    }
//                }
//                if let liveKitVoiceSession, liveKitVoiceSession.isRecording {
//                    RecView()
//                }
//            }
//        }
//        else if let scheduledAt = liveEvent.scheduledAt {
//            HStack {
//                Image(systemName: "calendar")
//                Text(scheduledAt.formatted())
//            }
//                .padding(.top, 10)
//                .font(.footnote)
//                .foregroundColor(theme.secondary)
//        }
//        
//        Text(liveEvent.title ?? " ")
//            .font(.title)
//            .fontWeightBold()
//            .lineLimit(2)
//        
//        if let summary = liveEvent.summary, (liveEvent.title ?? "") != summary {
//            Text(summary)
//                .lineLimit(20)
//        }
//        
//        if let roomAddress {
//            CopyableTextView(text: roomAddress, copyText: "nostr:" + roomAddress)
//                .foregroundColor(Color.gray)
//                .lineLimit(1)
//                .truncationMode(.tail)
//                .frame(maxWidth: 140)
//                .toolbar {
//                    ToolbarItem(placement: .topBarTrailing) {
//                        Button("Share", systemImage: "square.and.arrow.up") {
//                            if !IS_CATALYST && !IS_IPAD {
//                                LiveKitVoiceSession.shared.visibleNest = nil
//                            }
//                            Drafts.shared.draft = "\(liveEvent.title ?? "Join") 👇\n\n" + "nostr:" + roomAddress
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                                sendNotification(.newTemplatePost)
//                            }
//                        }
//                    }
//                }
//        }
////#if DEBUG
////        Text("copy event json")
////            .onTapGesture {
////                UIPasteboard.general.string = liveEvent.eventJson
////            }
////#endif
//    }
//    
//    @ViewBuilder
//    private var participantsView: some View {
//        
//        // ON STAGE
//        if !liveEvent.onStage.isEmpty {
//            ScrollView(.horizontal) {
//                HFlow(alignment: .top) {
//                    ForEach(liveEvent.onStage.indices, id: \.self) { index in
////                        NBNavigationLink(value: NRContactPath(nrContact: liveEvent.onStage[index], navigationTitle: liveEvent.onStage[index].anyName), label: {
//                            NestParticipantView(
//                                nrContact: liveEvent.onStage[index],
//                                role: liveEvent.role(forPubkey: liveEvent.onStage[index].pubkey),
//                                aTag: liveEvent.id,
//                                showControls: liveEvent.liveKitConnectUrl != nil
//                            )
//                            .onTapGesture {
////                                guard liveEvent.liveKitConnectUrl != nil else { return } // only for nests for now because navigation issues / video stream doesn't continue in bg
//                                if liveEvent.onStage[index] == selectedContact {
//                                    selectedContact = nil
//                                }
//                                else {
//                                    selectedContact = liveEvent.onStage[index]
//                                }
//                            }
////                        })
//                        .id(liveEvent.onStage[index].pubkey)
//                        .frame(width: 95, height: 95)
//                        .fixedSize()
//                    }
//                }
////                .frame(height: liveEvent.onStage.count > 4 ? 200 : 100)
//                .frame(height: 100)
//            }
//        }
//        
//        if !liveEvent.listeners.isEmpty {
//            if liveEvent.listeners.count > 4 {
//                Text("\(liveEvent.listeners.count) listeners")
//                    .frame(maxWidth: .infinity, alignment: .trailing)
//                    .font(.footnote)
//                    .foregroundColor(Color.gray)
//            }
//            Divider()
//        }
//        
//        // OTHERS PRESENT (ROOM PRESENCE 10312)
//        if !liveEvent.listeners.isEmpty  {
//            ScrollView(.horizontal) {
//                HFlow(alignment: .top) {
//                    ForEach(liveEvent.listeners.indices, id: \.self) { index in
////                        NBNavigationLink(value: NRContactPath(nrContact: liveEvent.listeners[index], navigationTitle: liveEvent.listeners[index].anyName), label: {
//                            NestParticipantView(
//                                nrContact: liveEvent.listeners[index],
//                                role: liveEvent.role(forPubkey: liveEvent.listeners[index].pubkey),
//                                aTag: liveEvent.id,
//                                showControls: false
//                            )
//                            .onTapGesture {
////                                guard liveEvent.liveKitConnectUrl != nil else { return } // only for nests for now because navigation issues / video stream doesn't continue in bg
//                                if liveEvent.listeners[index] == selectedContact {
//                                    selectedContact = nil
//                                }
//                                else {
//                                    selectedContact = liveEvent.listeners[index]
//                                }
//                            }
////                        })
//                        .id(liveEvent.listeners[index].pubkey)
//                        .frame(width: 95, height: 95)
//                        .fixedSize()
//                    }
//                }
////                .frame(height: liveEvent.listeners.count > 4 ? 200 : 100)
//                .frame(height: 100)
//            }
//        }
//    }
//    
//    @ViewBuilder
//    private var nestButtonsView: some View {
//        if let liveKitVoiceSession {
//            if let scheduledAt = liveEvent.scheduledAt, liveEvent.status == "planned" {
//                ScheduleReminderButton(at: scheduledAt, reminderId: liveEvent.id)
//            }
//            else if liveEvent.streamHasEnded {
//                EmptyView()
//            }
//            else if case .connected = liveKitVoiceSession.state {
//                NestButtons(liveKitVoiceSession: liveKitVoiceSession)
//                    .frame(height: 100)
//            }
//            else if case .connecting = liveKitVoiceSession.state {
//                Button { } label: {
//                    Image(systemName: "hourglass")
//                        .foregroundColor(.white)
//                        .frame(maxWidth: .infinity, alignment: .center)
//                }
//                .buttonStyle(NosturButton(height: 36, bgColor: theme.accent))
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(.horizontal, 10)
//                .disabled(true)
//            }
//            else if let connectUrl = liveEvent.liveKitConnectUrl, case .disconnected = liveKitVoiceSession.state {
//                VStack(spacing: 25) {
//                    Button {
//                        if liveKitVoiceSession.listenAnonymously {
//                            liveEvent.joinRoomAnonymously(keys: liveKitVoiceSession.anonymousKeys) { authToken in
//                                liveKitVoiceSession.connect(connectUrl, token: authToken, accountType: .anonymous(liveKitVoiceSession.anonymousKeys), nrLiveEvent: liveEvent)
//                            }
//                        }
//                        else {
//                            guard let account = account else { return }
//                            
//                            liveEvent.joinRoom(account: account) { authToken in
//                                liveKitVoiceSession.connect(connectUrl, token: authToken, accountType: .account(account), nrLiveEvent: liveEvent)
//                            }
//                        }
//                    } label: {
//                        HStack {
//                            if liveKitVoiceSession.listenAnonymously {
//                                ZStack {
//                                    Circle()
//                                        .foregroundColor(Color.gray)
//                                        .frame(height: 26)
//                                    Image(systemName: "sunglasses.fill")
//                                        .foregroundColor(Color.black)
//                                }
//                            }
//                            else if let account {
//                                MiniPFP(pictureUrl: account.pictureUrl, size: 20.0)
//                            }
//                            Text("Start listening")
//                        }
//                        .frame(maxWidth: .infinity, alignment: .center)
//                    }
//                    .buttonStyle(NosturButton(height: 36, bgColor: theme.accent))
//                    .frame(maxWidth: .infinity, alignment: .center)
//                    .disabled(liveKitVoiceSession.room.connectionState != .disconnected)
//                    
//                    Toggle(isOn: $liveKitVoiceSession.listenAnonymously) {
//                        Text("Listen anonymously")
//                    }
//                }
//                .padding(.horizontal, 10)
//            }
//            else if case .error(let error) = liveKitVoiceSession.state {
//                Text(error)
//            }
//            else if let webUrl = liveEvent.webUrl, let webUrlURL = URL(string: webUrl) {
//                Button {
//                    UIApplication.shared.open(webUrlURL)
//                } label: {
//                    Text("View on web")
//                        .frame(maxWidth: .infinity, alignment: .center)
//                }
//                .buttonStyle(NosturButton(height: 36))
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(.horizontal, 10)
//            }
//        }
//    }
//    
//    @ViewBuilder
//    private var videoStreamView: some View {
//        if liveEvent.streamHasEnded, let recordingUrl = liveEvent.recordingUrl, let url = URL(string: recordingUrl) {
//            EmbeddedVideoView(url: url, pubkey: liveEvent.pubkey, availableWidth: videoWidth, autoload: true, didStart: $didStart, thumbnail: liveEvent.thumbUrl)
//        }
//        else if liveEvent.streamHasEnded {
//            EmptyView()
//        }
//        else if let url = liveEvent.url {
//            if url.absoluteString.suffix(5) == ".m3u8" {
//                EmbeddedVideoView(url: url, pubkey: liveEvent.pubkey, availableWidth: videoWidth, autoload: true, didStart: $didStart, thumbnail: liveEvent.thumbUrl)
//            }
//            else if liveEvent.liveKitConnectUrl == nil {
//                Button {
//                    UIApplication.shared.open(url)
//                } label: {
//                    Text("Go to stream")
//                        .frame(maxWidth: .infinity, alignment: .center)
//                }
//                .buttonStyle(NosturButton(height: 36))
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(.horizontal, 10)
//            }
//        }
//    }
//    
//    @ViewBuilder
//    private var recordingsMenu: some View {
//        Menu {
//            if (liveEvent.status == "live" || liveEvent.status == "planned") && liveEvent.pubkey == account?.publicKey {
//                Button("Close room", systemImage: "xmark.app") {
//                    guard let account, account.publicKey == liveEvent.pubkey else { return }
//                    
//                    var closedNEvent = liveEvent.nEvent
//                    closedNEvent.createdAt = NTimestamp(date: .now)
//                    closedNEvent.tags = closedNEvent.tags.map { tag in
//                        if tag.type == "status" {
//                            return NostrTag(["status", "ended"])
//                        }
//                        else if tag.type == "ends" {
//                            return NostrTag(["ends", Int(Date.now.timeIntervalSince1970).description])
//                        }
//                        return tag
//                    }
//                    if !closedNEvent.tags.contains(where: { $0.type == "ends" }) {
//                        closedNEvent.tags.append(NostrTag(["ends", Int(Date.now.timeIntervalSince1970).description]))
//                    }
//                    if account.isNC {
//                        NSecBunkerManager.shared.requestSignature(forEvent: closedNEvent, usingAccount: account) { signedClosedNEvent in
//                            Unpublisher.shared.publishNow(signedClosedNEvent, skipDB: true)
//                            MessageParser.shared.handleNormalMessage(message: NXRelayMessage(relays: "local", type: .EVENT, message: "", event: signedClosedNEvent), nEvent: signedClosedNEvent, relayUrl: "local")
//                            liveEvent.status = "ended"
//                        }
//                    }
//                    else {
//                        if let signedClosedNEvent = try? account.signEvent(closedNEvent) {
//                            Unpublisher.shared.publishNow(signedClosedNEvent, skipDB: true)
//                            MessageParser.shared.handleNormalMessage(message: NXRelayMessage(relays: "local", type: .EVENT, message: "", event: signedClosedNEvent), nEvent: signedClosedNEvent, relayUrl: "local")
//                            liveEvent.status = "ended"
//                        }
//                    }
//                    
//                }
//            }
//            else if liveEvent.status == "ended" && liveEvent.pubkey == account?.publicKey {
//                Button("Restart room", systemImage: "restart.circle") {
//                    guard let account, account.publicKey == liveEvent.pubkey else { return }
//                    
//                    var restartedNEvent = liveEvent.nEvent
//                    restartedNEvent.createdAt = NTimestamp(date: .now)
//                    restartedNEvent.tags = restartedNEvent.tags.compactMap { tag in
//                        if tag.type == "status" {
//                            return NostrTag(["status", "live"])
//                        }
//                        else if tag.type == "ends" {
//                            return nil
//                        }
//                        return tag
//                    }
//
//                    if account.isNC {
//                        NSecBunkerManager.shared.requestSignature(forEvent: restartedNEvent, usingAccount: account) { signedRestartedNEvent in
//                            Unpublisher.shared.publishNow(signedRestartedNEvent, skipDB: true)
//                            MessageParser.shared.handleNormalMessage(message: NXRelayMessage(relays: "local", type: .EVENT, message: "", event: signedRestartedNEvent), nEvent: signedRestartedNEvent, relayUrl: "local")
//                            liveEvent.status = "live"
//                        }
//                    }
//                    else {
//                        if let signedRestartedNEvent = try? account.signEvent(restartedNEvent) {
//                            Unpublisher.shared.publishNow(signedRestartedNEvent, skipDB: true)
//                            MessageParser.shared.handleNormalMessage(message: NXRelayMessage(relays: "local", type: .EVENT, message: "", event: signedRestartedNEvent), nEvent: signedRestartedNEvent, relayUrl: "local")
//                            liveEvent.status = "live"
//                        }
//                    }
//                    
//                }
//            }
//                
//            Text("Recordings")
//                .font(.footnote)
//            if !liveKitVoiceSession.isRecording {
//                Button("Start recording", systemImage: "record.circle") {
//                    guard let account else { return }
//                    Task { @MainActor in
//                        try? await liveEvent.startRecording(account: account)
//                        if let recordings = try? await liveEvent.listRecordings(account: account) {
//                            Task { @MainActor in
//                                self.recordings = recordings
//                            }
//                        }
//                    }
//                }
//            }
//            if let recordings {
//                ForEach(recordings) { recording in
//                    Button("\(recording.stopped != nil ? "Recorded" : "Recording since") \(Date(timeIntervalSince1970: TimeInterval(recording.started)).formatted(date: .omitted, time: .shortened))", systemImage: recording.stopped != nil ? "arrow.down.circle" : "stop.circle") {
//                        guard let account else { return }
//                        if recording.stopped == nil {
//                            // stop
//                            Task { @MainActor in
//                                try? await liveEvent.stopRecording(account: account, recordingId: recording.id)
//                                
//                                // refresh list
//                                if let recordings = try? await liveEvent.listRecordings(account: account) {
//                                    Task { @MainActor in
//                                        self.recordings = recordings
//                                    }
//                                }
//                            }
//                        }
//                        else {
//                            // download
//                            L.og.debug("Download recording.......")
//                            guard let url = URL(string: recording.url) else { return }
//                            UIApplication.shared.open(url)
//                        }
//                        
//                    }
//                    .foregroundColor(recording.stopped != nil ? Color.red : Color.primary)
//                }
//            }
//            else {
//                ProgressView()
//                    .task {
//                        guard let account else { return }
//                        if let recordings = try? await liveEvent.listRecordings(account: account) {
//                            Task { @MainActor in
//                                self.recordings = recordings
//                            }
//                        }
//                    }
//            }
//        } label: {
//            Image(systemName: "gearshape.fill")
//                .font(.title2)
//                .padding()
//        }
//    }
//    
//}
