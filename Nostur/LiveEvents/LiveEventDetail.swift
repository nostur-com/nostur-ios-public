//
//  LiveEventDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import LiveKit
import SwiftUI
import SwiftUIFlow
import NavigationBackport

struct LiveEventDetail: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var themes: Themes
    @ObservedObject public var liveEvent: NRLiveEvent
    @ObservedObject public var liveKitVoiceSession: LiveKitVoiceSession = .shared
    
    @State private var didStart = false
    @State private var account: CloudAccount? = nil
    
    
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: 4)
    @State private var rows = [GridItem(.fixed(80)), GridItem(.fixed(80))]
    
    private var streamHasEnded: Bool {
        if let status = liveEvent.status, status == "ended" {
            return true
        }
        return false
    }
    
    private var videoWidth: CGFloat {
        dim.listWidth + (DIMENSIONS.BOX_PADDING*2)
    }
    
    @State private var zapCustomizerSheetInfo: ZapCustomizerSheetInfo? = nil
    @State private var showZapSheet = false
    
    @State private var selectedContact: NRContact? = nil
    
    // TODO: Somehow get the width somewhere on parent views
    @State private var vc: ViewingContext?
    
    private var showModeratorControls: Bool {
        if liveKitVoiceSession.listenAnonymously { return false }
        guard let account else { return false }
        return liveEvent.admins.contains(account.publicKey) || liveEvent.pubkey == account.publicKey
    }
    
    @State private var recordings: [RecordingInfo]? = nil
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        if let vc {
                            VStack {
                                headerView
                                
                                participantsView
                                    .onReceive(receiveNotification(.showZapCustomizerSheet)) { notification in
                                        let zapCustomizerSheetInfo = notification.object as! ZapCustomizerSheetInfo
                                        guard zapCustomizerSheetInfo.zapAtag != nil else { return }
                                        self.showZapSheet = true
                                        self.zapCustomizerSheetInfo = zapCustomizerSheetInfo
                                    }
                                
                                videoStreamView
                                    .background(themes.theme.background)
                            }
                            
                            ZStack {
                                ChatRoom(aTag: liveEvent.id, theme: themes.theme, anonymous: liveKitVoiceSession.listenAnonymously)
                                    .frame(minHeight: UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular ? 250 : 150, maxHeight: .infinity)
                                    .padding(.horizontal, 10)
                                    .environmentObject(vc)
                                
                                if let selectedContact {
                                    themes.theme.background
                                    
                                    SelectedParticipantView(nrContact: selectedContact, showZapButton: !liveKitVoiceSession.listenAnonymously, liveEvent: liveEvent, showModeratorControls: showModeratorControls, selectedContact: $selectedContact)
                                        .padding(10)
                                }
                            }
                        }
                    }
                    .frame(minHeight: geo.size.height)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    nestButtonsView
                        .padding(10)
                        .layoutPriority(1)
                }
                .background(themes.theme.background)
            }
            .onAppear {
                vc = ViewingContext(availableWidth: dim.articleRowImageWidth(), fullWidthImages: false, theme: themes.theme, viewType: .row)
                liveEvent.fetchPresenceFromRelays()
                if liveEvent.liveKitConnectUrl != nil && !liveKitVoiceSession.listenAnonymously {
                    account = Nostur.account()
                }
            }
            .background(themes.theme.background)
            .preference(key: TabTitlePreferenceKey.self, value: liveEvent.title ?? "(Stream)")
            .withNavigationDestinations()
            .nbNavigationDestination(isPresented: $showZapSheet, destination: {
                if let zapCustomizerSheetInfo {
                    ZapCustomizerSheet(name: zapCustomizerSheetInfo.name, customZapId: zapCustomizerSheetInfo.customZapId, supportsZap: true)
                        .environmentObject(NRState.shared)
                        .presentationDetentsLarge()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
            })
            .sheet(item: $selectedContact) { nrContact in
                NBNavigationStack {
                    SelectedParticipantView(nrContact: nrContact, showZapButton: !liveKitVoiceSession.listenAnonymously, liveEvent: liveEvent, showModeratorControls: showModeratorControls, selectedContact: $selectedContact)
                        .environmentObject(themes)
                        .padding(10)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.background)
                .presentationDetents45ml()
            }
    }
    
    @ViewBuilder
    private var headerView: some View {
        if streamHasEnded {
            HStack {
                Text("Stream has ended")
                    .foregroundColor(.secondary)
            }
        }
        else if liveEvent.totalParticipants > 0 || liveKitVoiceSession.isRecording {
            HStack {
                if liveEvent.totalParticipants > 0 {
                    Text("\(liveEvent.totalParticipants) participants")
                        .foregroundColor(.secondary)
                }
                if liveKitVoiceSession.isRecording {
                    RecView()
                }
            }
        }
        else if let scheduledAt = liveEvent.scheduledAt {
            HStack {
                Image(systemName: "calendar")
                Text(scheduledAt.formatted())
            }
                .padding(.top, 10)
                .font(.footnote)
                .foregroundColor(themes.theme.secondary)
        }
        
        if let title = liveEvent.title {
            Text(title)
                .font(.title)
                .fontWeightBold()
                .lineLimit(2)
        }
        
        if let summary = liveEvent.summary, (liveEvent.title ?? "") != summary {
            Text(summary)
                .lineLimit(20)
        }
        
#if DEBUG
        Text("copy event json")
            .onTapGesture {
                UIPasteboard.general.string = liveEvent.eventJson
            }
#endif
    }
    
    @ViewBuilder
    private var participantsView: some View {
        
        // ON STAGE
        if !liveEvent.onStage.isEmpty {
            ScrollView(.horizontal) {
                HFlow(alignment: .top) {
                    ForEach(liveEvent.onStage.indices, id: \.self) { index in
//                        NBNavigationLink(value: NRContactPath(nrContact: liveEvent.onStage[index], navigationTitle: liveEvent.onStage[index].anyName), label: {
                            NestParticipantView(
                                nrContact: liveEvent.onStage[index],
                                role: liveEvent.role(forPubkey: liveEvent.onStage[index].pubkey),
                                aTag: liveEvent.id
                            )
                            .onTapGesture {
                                if liveEvent.onStage[index] == selectedContact {
                                    selectedContact = nil
                                }
                                else {
                                    selectedContact = liveEvent.onStage[index]
                                }
                            }
//                        })
                        .id(liveEvent.onStage[index].pubkey)
                        .frame(width: 95, height: 95)
                        .fixedSize()
                    }
                }
//                .frame(height: liveEvent.onStage.count > 4 ? 200 : 100)
                .frame(height: 100)
            }
        }
        
        if !liveEvent.listeners.isEmpty {
            if liveEvent.listeners.count > 4 {
                Text("\(liveEvent.listeners.count) listeners")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.footnote)
                    .foregroundColor(Color.gray)
            }
            Divider()
        }
        
        // OTHERS PRESENT (ROOM PRESENCE 10312)
        if !liveEvent.listeners.isEmpty {
            ScrollView(.horizontal) {
                HFlow(alignment: .top) {
                    ForEach(liveEvent.listeners.indices, id: \.self) { index in
//                        NBNavigationLink(value: NRContactPath(nrContact: liveEvent.listeners[index], navigationTitle: liveEvent.listeners[index].anyName), label: {
                            NestParticipantView(
                                nrContact: liveEvent.listeners[index],
                                role: liveEvent.role(forPubkey: liveEvent.listeners[index].pubkey),
                                aTag: liveEvent.id,
                                showControls: false
                            )
                            .onTapGesture {
                                if liveEvent.listeners[index] == selectedContact {
                                    selectedContact = nil
                                }
                                else {
                                    selectedContact = liveEvent.listeners[index]
                                }
                            }
//                        })
                        .id(liveEvent.listeners[index].pubkey)
                        .frame(width: 95, height: 95)
                        .fixedSize()
                    }
                }
//                .frame(height: liveEvent.listeners.count > 4 ? 200 : 100)
                .frame(height: 100)
            }
        }
    }
    
    @ViewBuilder
    private var nestButtonsView: some View {
        if let scheduledAt = liveEvent.scheduledAt, liveEvent.status == "planned" {
            ScheduleReminderButton(at: scheduledAt, reminderId: liveEvent.id)
        }
        else if streamHasEnded {
            EmptyView()
        }
        else if case .connected = liveKitVoiceSession.state {
            NestButtons(liveKitVoiceSession: liveKitVoiceSession)
                .frame(height: 100)
        }
        else if case .connecting = liveKitVoiceSession.state {
            Button { } label: {
                Image(systemName: "hourglass")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(NosturButton(height: 36, bgColor: themes.theme.accent))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .disabled(true)
        }
        else if let connectUrl = liveEvent.liveKitConnectUrl, case .disconnected = liveKitVoiceSession.state {
            VStack(spacing: 25) {
                Button {
                    if liveKitVoiceSession.listenAnonymously {
                        liveEvent.joinRoomAnonymously(keys: liveKitVoiceSession.anonymousKeys) { authToken in
                            liveKitVoiceSession.connect(connectUrl, token: authToken, accountType: .anonymous(liveKitVoiceSession.anonymousKeys), nrLiveEvent: liveEvent)
                        }
                    }
                    else {
                        guard let account = account else { return }
                        
                        liveEvent.joinRoom(account: account) { authToken in
                            liveKitVoiceSession.connect(connectUrl, token: authToken, accountType: .account(account), nrLiveEvent: liveEvent)
                        }
                    }
                } label: {
                    HStack {
                        if liveKitVoiceSession.listenAnonymously {
                            ZStack {
                                Circle()
                                    .foregroundColor(Color.gray)
                                    .frame(height: 26)
                                Image(systemName: "sunglasses.fill")
                                    .foregroundColor(Color.black)
                            }
                        }
                        else if let account {
                            MiniPFP(pictureUrl: account.pictureUrl, size: 20.0)
                        }
                        Text("Start listening")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(NosturButton(height: 36, bgColor: themes.theme.accent))
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(liveKitVoiceSession.room.connectionState != .disconnected)
                
                Toggle(isOn: $liveKitVoiceSession.listenAnonymously) {
                    Text("Listen anonymously")
                }
            }
            .padding(.horizontal, 10)
        }
        else if case .error(let error) = liveKitVoiceSession.state {
            Text(error)
        }
        else if let webUrl = liveEvent.webUrl, let webUrlURL = URL(string: webUrl) {
            Button {
                UIApplication.shared.open(webUrlURL)
            } label: {
                Text("View on web")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(NosturButton(height: 36))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
        }
    }
    
    @ViewBuilder
    private var videoStreamView: some View {
        if streamHasEnded, let recordingUrl = liveEvent.recordingUrl, let url = URL(string: recordingUrl) {
            NosturVideoViewur(url: url,  pubkey: liveEvent.pubkey, height: videoWidth * 9/16, videoWidth: videoWidth, autoload: true, theme: Themes.default.theme, didStart: $didStart, thumbnail: liveEvent.thumbUrl)
        }
        else if streamHasEnded {
            EmptyView()
        }
        else if let url = liveEvent.url {
            if url.absoluteString.suffix(5) == ".m3u8" {
                NosturVideoViewur(url: url,  pubkey: liveEvent.pubkey, height: videoWidth * 9/16, videoWidth: videoWidth, autoload: true, theme: Themes.default.theme, didStart: $didStart, thumbnail: liveEvent.thumbUrl)
            }
            else if liveEvent.liveKitConnectUrl == nil {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Go to stream")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(NosturButton(height: 36))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
            }
        }
    }
    
    @ViewBuilder
    private var recordingsMenu: some View {
        Menu {
            if liveEvent.status == "live" || liveEvent.status == "planned" {
                Button("Close room", systemImage: "xmark.app") {
                    guard let account, account.publicKey == liveEvent.pubkey else { return }
                    
                    var closedNEvent = liveEvent.nEvent
                    closedNEvent.createdAt = NTimestamp(date: .now)
                    closedNEvent.tags = closedNEvent.tags.map { tag in
                        if tag.type == "status" {
                            return NostrTag(["status", "ended"])
                        }
                        else if tag.type == "ends" {
                            return NostrTag(["ends", Int(Date.now.timeIntervalSince1970).description])
                        }
                        return tag
                    }
                    if !closedNEvent.tags.contains(where: { $0.type == "ends" }) {
                        closedNEvent.tags.append(NostrTag(["ends", Int(Date.now.timeIntervalSince1970).description]))
                    }
                    if account.isNC {
                        NSecBunkerManager.shared.requestSignature(forEvent: closedNEvent, usingAccount: account) { signedClosedNEvent in
                            Unpublisher.shared.publishNow(signedClosedNEvent, skipDB: true)
                            MessageParser.shared.handleNormalMessage(message: RelayMessage(relays: "local", type: .EVENT, message: "", event: signedClosedNEvent), nEvent: signedClosedNEvent, relayUrl: "local")
                            liveEvent.status = "ended"
                        }
                    }
                    else {
                        if let signedClosedNEvent = try? account.signEvent(closedNEvent) {
                            Unpublisher.shared.publishNow(signedClosedNEvent, skipDB: true)
                            MessageParser.shared.handleNormalMessage(message: RelayMessage(relays: "local", type: .EVENT, message: "", event: signedClosedNEvent), nEvent: signedClosedNEvent, relayUrl: "local")
                            liveEvent.status = "ended"
                        }
                    }
                    
                }
            }
                
            Text("Recordings")
                .font(.footnote)
            if !liveKitVoiceSession.isRecording {
                Button("Start recording", systemImage: "record.circle") {
                    guard let account else { return }
                    Task { @MainActor in
                        try? await liveEvent.startRecording(account: account)
                        if let recordings = try? await liveEvent.listRecordings(account: account) {
                            Task { @MainActor in
                                self.recordings = recordings
                            }
                        }
                    }
                }
            }
            if let recordings {
                ForEach(recordings) { recording in
                    Button("\(recording.stopped != nil ? "Recorded" : "Recording since") \(Date(timeIntervalSince1970: TimeInterval(recording.started)).formatted(date: .omitted, time: .shortened))", systemImage: recording.stopped != nil ? "arrow.down.circle" : "stop.circle") {
                        guard let account else { return }
                        if recording.stopped == nil {
                            // stop
                            Task { @MainActor in
                                try? await liveEvent.stopRecording(account: account, recordingId: recording.id)
                                
                                // refresh list
                                if let recordings = try? await liveEvent.listRecordings(account: account) {
                                    Task { @MainActor in
                                        self.recordings = recordings
                                    }
                                }
                            }
                        }
                        else {
                            // download
                            L.og.debug("Download recording.......")
                            guard let url = URL(string: recording.url) else { return }
                            UIApplication.shared.open(url)
                        }
                        
                    }
                    .foregroundColor(recording.stopped != nil ? Color.red : Color.primary)
                }
            }
            else {
                ProgressView()
                    .task {
                        guard let account else { return }
                        if let recordings = try? await liveEvent.listRecordings(account: account) {
                            Task { @MainActor in
                                self.recordings = recordings
                            }
                        }
                    }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .padding()
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadContactLists()
        pe.loadFollows()
        pe.parseMessages([
            
            // host profile info
            ###"["EVENT", "contact", {"kind":0,"id":"763a7412148cca4074e9e68a0bc16e5bd1821524bdc5593cb178de199e42fcc6","pubkey":"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","created_at":1719904036,"tags":[],"content":"{\"name\":\"ZapLamp\",\"picture\":\"https://nostrver.se/sites/default/files/2024-07/IMG_1075.jpeg\",\"about\":\"A side-project of @npub1qe3e5wrvnsgpggtkytxteaqfprz0rgxr8c3l34kk3a9t7e2l3acslezefe Send some sats with a zap to see the lamp flash on the livestream\",\"website\":\"https://nostrver.se\",\"lud16\":\"sebastian@lnd.sebastix.com\",\"display_name\":\"ZapLamp ⚡💜\",\"displayName\":\"ZapLamp ⚡💜\",\"nip05\":\"zaplamp@nostrver.se\",\"pubkey\":\"9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85\"}","sig":"e1266f8131cae6a457791114cda171031b79538f8bd710fbef45a2c36265045eb641914719b949509dcbf725c2b1f8522dffb5556b3e3f7d4db9d039a9e6daa0"}]"###,
            
            // live event
            ###"["EVENT","LIVEEVENT-LIVE2",{"kind":30311,"id":"03082afe5364b086293a60c3fc982d5265083af66b726cecd0978d3f0d5be1e0","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1720098927,"tags":[["d","569180c5-adec-40a6-a41b-513f39ded13a"],["title",""],["summary","Send a zap to flash the lamp! There is a ~15 sec between your zap and the stream."],["image","https://dvr.zap.stream/zap-stream-dvr/569180c5-adec-40a6-a41b-513f39ded13a/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277007695\u0026Signature=Zqbwvwam70uT9UKRBW0fmHHzLrI%3D"],["status","live"],["p","9a470d841f9aa3f87891cd76a2e14a3441d015dbd8fc2b270b5ac8a9d9566e85","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1719911364"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/569180c5-adec-40a6-a41b-513f39ded13a.m3u8"],["current_participants","0"],["t","zaplamp"],["t","lnbits"],["t","zapathon"],["t","internal:art"],["goal","66d73e8f3de742e70e3f5b1c30ff2a028fae0d4f1efad53089172e5c05563579"]],"content":"","sig":"4321619ff3aa63387aefc7403baea01317a7c408cfa2547546046e354e4a765af886ee9c509f1ca6043be7cf01bdff696cf521261316c5261a2a42eed87e5289"}]"###,
            
            // profile
            ###"["EVENT", "x", {"kind":0,"id":"63617e02e87940abf6ecc93368330adae663538237d171d4e5177465f5208eba","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1712224322,"tags":[],"content":"{\"nip05\":\"_@zap.stream\",\"name\":\"zap.stream\",\"picture\":\"https://zap.stream/logo.png\",\"website\":\"https://zap.stream\",\"about\":\"Keep 100% of your tips when you stream with http://zap.stream! Powered by #bitcoin \u0026 #nostr\"}","sig":"316c38e1b67d4757bf152ec3c4756a1c9f3d47218fef8b06c5bacf7c96c27e1ce6297caf7a7c7887f9b01f6c92f2d4b26722722062b2243f44c252d0d432eefc"}]"###,
            
            // live event
            ###"["EVENT", "LIVEEVENT-LIVE", {"kind":30311,"id":"8619e382aec444d046fbea90c4ee1b791d9a6e509deb6e6328f7a050dc54f601","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1720103970,"tags":[["d","34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f"],["title","BTC Sessions LIVE"],["summary","You are the DJ on Noderunners Radio!"],["image","https://dvr.zap.stream/zap-stream-dvr/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33277012770\u0026Signature=n4l1GWDFvBLm8ZtAp%2BIss%2BjmBUk%3D"],["status","live"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","","speaker"],["p","e774934cb65e2b29e3b34f8b2132df4492bc346ba656cc8dc2121ff407688de0","","host"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","","speaker"],["p","eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","","speaker"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1720089226"],["service","https://api.zap.stream/api/nostr"],["streaming","https://data.zap.stream/stream/34846ce3-d0f7-4ac9-bbb0-1a7a453acd2f.m3u8"],["current_participants","2"],["t","Jukebox"],["t","Music"],["t","Radio"],["t","24/7"],["t","Pleb-Rule"],["goal","1b8460c1f1590aecd340fcb327c21fb466f46800aba7bd7b6ac6b0a2257f7789"]],"content":"","sig":"d3b07150e70a36009a97c0953d8c2c759b364301e92433cb0a31d5dcfffc2dabcc6d6f330054a2cae30a7ecc16dbd8ddf1e05f9b7553c88a5d9dece18a2000bc"}]"###
        ])
        pe.parseMessages([
            ###"["EVENT","e",{"kind":30311,"id":"75558b5933f0b7002df3dbe5356df2ab1144f8c0595e8d60282382a2007d5ed7","pubkey":"cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5","created_at":1721669595,"tags":[["d","82d27633-1dd1-4b38-8f9d-f6ab9b31fc83"],["title","Fiatjaf \u0026 utxo play dominion"],["summary","Come watch this very exciting game"],["image","https://dvr.zap.stream/zap-stream-dvr/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83/thumb.jpg?AWSAccessKeyId=2gmV0suJz4lt5zZq6I5J\u0026Expires=33278578238\u0026Signature=X4Jo1oAm5pIg0YZ40CobUUdpD2A%3D"],["status","ended"],["p","e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","","host"],["relays","wss://relay.snort.social","wss://nos.lol","wss://relay.damus.io","wss://relay.nostr.band","wss://nostr.land","wss://nostr-pub.wellorder.net","wss://nostr.wine","wss://relay.nostr.bg","wss://nostr.oxtr.dev"],["starts","1721664799"],["service","https://api.zap.stream/api/nostr"],["recording","https://data.zap.stream/recording/82d27633-1dd1-4b38-8f9d-f6ab9b31fc83.m3u8"],["ends","1721669595"]],"content":"","sig":"3f03a0de44dd2eec8dd045d5dd2242d1558f2af7719955e9ceb300c4ee14f26e4a170b13db923fb313bf4fd5d2c60be344f7901ea3ef5dd7f0fcb8df908b8b21"}]"###,
            ###"["EVENT","LIVE",{"content":"","created_at":1718076971,"id":"1460f66179e5c33e0d15b580b73773e2965f0548448efe7e22ecc98355e13bb2","kind":30311,"pubkey":"8a0969377e9abfe215e99f02e1789437892526b1d1e0b1ca4ed7cbf88b1cc421","sig":"2eb76ceda6c1345465998fe14cf53da308880fd1cf2f70e6c0d6e248d1a903105301f99f04c8e230272aaf0c8ee5a35c7c2b03cc63e64e62e88b7b55111f3920","tags":[["d","1718063831277"],["title","Corny Chat News"],["summary","Weekly news roundup providing a summary of the weeks headlines and topical discussion regarding Nostr, Lightning, Bitcoin, Geopolitics and Clown World, Humor and more."],["image","https://image.nostr.build/ea30115d83b1d3c303095a0a3349514ca2a88e12b9c5dd7fd92e984502be55f0.jpg"],["service","https://cornychat.com/cornychatnews"],["streaming","https://cornychat.com/cornychatnews"],["starts","1718063831"],["ends","1718080571"],["status","live"],["current_participants","7"],["t","talk"],["t","talk show"],["L","com.cornychat"],["l","cornychat.com","com.cornychat"],["l","audiospace","com.cornychat"],["r","https://cornychat.com/cornychatnews"],["p","50809a53fef95904513a840d4082a92b45cd5f1b9e436d9d2b92a89ce091f164","","Participant"],["p","7cc328a08ddb2afdf9f9be77beff4c83489ff979721827d628a542f32a247c0e","","Participant"],["p","21b419102da8fc0ba90484aec934bf55b7abcf75eedb39124e8d75e491f41a5e","","Room Owner"],["p","52387c6b99cc42aac51916b08b7b51d2baddfc19f2ba08d82a48432849dbdfb2","","Participant"],["p","50de492cfe5472450df1a0176fdf6d915e97cb5d9f8d3eccef7d25ff0a8871de","","Speaker"],["p","9322bd922f20c6fcd9e913454727b3bbc2d096be4811971055a826dda3d4cb0b","","Participant"],["p","cc76679480a4504b963a3809cba60b458ebf068c62713621dda94b527860447d","","Participant"]]}]"###
        ])
        pe.loadChats()
    }) {
        NBNavigationStack {
            if let liveEvent = PreviewFetcher.fetchEvent("75558b5933f0b7002df3dbe5356df2ab1144f8c0595e8d60282382a2007d5ed7") {
                let nrLiveEvent = NRLiveEvent(event: liveEvent)
                LiveEventDetail(liveEvent: nrLiveEvent)
            }
        }
    }
}








