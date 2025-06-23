//
//  StreamDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/07/2024.
//

import LiveKit
import SwiftUI
import SwiftUIFlow
import NavigationBackport
import NostrEssentials

// Copy pasted from LiveEventDetail() and changed to render as content within OverlayVideo { }
struct StreamDetail: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var themes: Themes
    @ObservedObject public var liveEvent: NRLiveEvent

    
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: 4)
    @State private var rows = [GridItem(.fixed(80)), GridItem(.fixed(80))]
    
    private var videoWidth: CGFloat {
        dim.listWidth + (DIMENSIONS.BOX_PADDING*2)
    }
    
    // Zap sheet NON-NWC
    @State private var paymentInfo: PaymentInfo? = nil // NON-NWC ZAP
    @State private var showNonNWCZapSheet = false // NON-NWC ZAP
    
    // Zap sheet NWC
    @State private var zapCustomizerSheetInfo: ZapCustomizerSheetInfo? = nil // NWC ZAP
    @State private var showZapSheet = false // NWC ZAP
    
    
    @State private var selectedContact: NRContact? = nil
    
    // TODO: Somehow get the width somewhere on parent views
    @State private var vc: ViewingContext?
    
    @State private var recordings: [RecordingInfo]? = nil
    
    @State private var roomAddress: String? = nil
    
    @State private var toggleReadMore: Bool = false
    @State private var contentExpanded: Bool = false
    @State private var sendSatsToWhoShown: Bool = false
    @ObservedObject private var apm: AnyPlayerModel = .shared
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        if apm.viewMode == .detailstream {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if let vc {
                        VStack {
                            videoStreamView
                                    .background(themes.theme.listBackground)
                        }
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                        }
                        
                        ChatRoom(aTag: liveEvent.id, theme: themes.theme, anonymous: false, chatVM: liveEvent.chatVM, selectedContact: $selectedContact)
                            .frame(minHeight: UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular ? 250 : 150, maxHeight: .infinity)
                            .padding(.horizontal, 5)
                            .padding(.bottom, 15)
                            .environmentObject(vc)
                            .overlay {
                                if sendSatsToWhoShown {
                                    themes.theme.listBackground
                                }
                            }
                        
                            .overlay(alignment: .top) {
                                VStack(spacing: 5) {
                                    if sendSatsToWhoShown {
                                        Text("Send sats to:")
                                            .padding(10)
                                            .font(.title2)
                                            .fontWeightBold()
                                            .frame(maxWidth: .infinity)
                                    }
                                    else {
                                        HStack {
                                            VStack {
                                                headerView
                                            }
                                            
                                            if !contentExpanded && shouldShowSatsButton {
                                                sendSatButton
                                                    .frame(width: 40)
                                                    .padding(.vertical, 3)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.trailing, 40)
                                    }
                                    
                                    if sendSatsToWhoShown {
                                        sendSatsToWho
                                            .onAppear {
                                                withAnimation {
                                                    satsReceivers = liveEvent.participantsOrSpeakers.filter { $0.anyLud }
                                                }
                                            }
                                            .onReceive(receiveNotification(.sendCustomZap)) { _ in
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                    withAnimation {
                                                        sendSatsToWhoShown = false
                                                    }
                                                }
                                            }
                                            .onReceive(receiveNotification(.showZapCustomizerSheet)) { notification in
                                                let zapCustomizerSheetInfo = notification.object as! ZapCustomizerSheetInfo
                                                guard zapCustomizerSheetInfo.zapAtag != nil else { return }
                                                self.showZapSheet = true
                                                self.zapCustomizerSheetInfo = zapCustomizerSheetInfo
                                            }
                                            .onReceive(receiveNotification(.showZapSheet)) { notification in
                                                let paymentInfo = notification.object as! PaymentInfo
                                                guard paymentInfo.zapAtag != nil else { return }
                                                self.paymentInfo = paymentInfo
                                                self.showNonNWCZapSheet = true
                                            }
                                    }
                                    
                                    if contentExpanded {
                                        participantsView
                                            .onReceive(receiveNotification(.showZapCustomizerSheet)) { notification in
                                                let zapCustomizerSheetInfo = notification.object as! ZapCustomizerSheetInfo
                                                guard zapCustomizerSheetInfo.zapAtag != nil else { return }
                                                self.showZapSheet = true
                                                self.zapCustomizerSheetInfo = zapCustomizerSheetInfo
                                            }
                                            .onReceive(receiveNotification(.showZapSheet)) { notification in
                                                let paymentInfo = notification.object as! PaymentInfo
                                                guard paymentInfo.zapAtag != nil else { return }
                                                self.paymentInfo = paymentInfo
                                                self.showNonNWCZapSheet = true
                                            }
                                    }
                                }
                                .background(.ultraThinMaterial)
                                .overlay(alignment: !contentExpanded ? .topTrailing : .bottomTrailing) {
                                    if !sendSatsToWhoShown {
                                        Button {
                                            withAnimation {
                                                contentExpanded.toggle()
                                            }
                                        } label: {
                                            Image(systemName: !contentExpanded ? "chevron.down" : "chevron.up")
                                                .padding()
                                                .contentShape(Rectangle())
                                        }
                                        .accessibilityHint(contentExpanded ? "Collapse" : "Expand")
                                        .buttonStyle(.plain)
                                    }
                                    else {
                                        Button {
                                            sendSatsToWhoShown = false
                                        } label: {
                                            Image(systemName: "multiply.circle.fill")
                                                .padding()
                                                .contentShape(Rectangle())
                                        }
                                        .accessibilityHint("Cancel")
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .onChange(of: liveEvent.participantsOrSpeakers) { nrContacts in
                                let missingPs = nrContacts
                                    .filter { $0.metadata_created_at == 0 }
                                    .map { $0.pubkey }

                                if !missingPs.isEmpty {
                                    QueuedFetcher.shared.enqueue(pTags: missingPs)
                                }
                                
                                satsReceivers = liveEvent.participantsOrSpeakers.filter { $0.anyLud }
                            }
                            .onAppear {
                                let missingPs = liveEvent.participantsOrSpeakers
                                    .filter { $0.metadata_created_at == 0 }
                                    .map { $0.pubkey }

                                if !missingPs.isEmpty {
                                    QueuedFetcher.shared.enqueue(pTags: missingPs)
                                }
                                
                                satsReceivers = liveEvent.participantsOrSpeakers.filter { $0.anyLud }
                            }
                    }
                }
                .frame(minHeight: geo.size.height)
                .onAppear {
                    vc = ViewingContext(availableWidth: min(600, dim.listWidth - 10), fullWidthImages: false, theme: themes.theme, viewType: .row)
                }
            }
            .toolbar {
                // VIEWERS / PARTICIPANTS / ...
                ToolbarItem(placement: .principal) {
                    if liveEvent.streamHasEnded {
                        Text("Session has ended")
                            .foregroundColor(.secondary)
                    }
                    else if liveEvent.totalParticipants > 0 {
                        Text("\(liveEvent.totalParticipants) viewers")
                            .foregroundColor(.secondary)
                    }
                    else if let scheduledAt = liveEvent.scheduledAt {
                        HStack {
                            Image(systemName: "calendar")
                            Text(scheduledAt.formatted())
                        }
                            .font(.footnote)
                            .foregroundColor(themes.theme.secondary)
                    }
                }
                
                // SHARE BUTTON
                ToolbarItem(placement: .topBarTrailing) {
                    if let roomAddress {
                        Button("Share", systemImage: "square.and.arrow.up") {
                            if !IS_CATALYST && !IS_IPAD {
                                AnyPlayerModel.shared.toggleViewMode()
                            }
                            Drafts.shared.draft = "\(liveEvent.title ?? "Watching") 👇\n\n" + "nostr:" + roomAddress
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                sendNotification(.newTemplatePost)
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(themes.theme.accent)
                        .font(.title2)
                        .offset(y: -5)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let relaysTag = liveEvent.nEvent.fastTags.first(where: { $0.0 == "relays" }) {
                    var relays: [String] = [normalizeRelayUrl(relaysTag.1)]
                    if let relay = relaysTag.2 {
                        relays = relays + [normalizeRelayUrl(relay)]
                    }
                    if let relay = relaysTag.3 {
                        relays = relays + [normalizeRelayUrl(relay)]
                    }
                    if let relay = relaysTag.4 {
                        relays = relays + [normalizeRelayUrl(relay)]
                    }
                    
                    if let bech32 = try? ShareableIdentifier(prefix: "naddr", kind: 30311, pubkey: liveEvent.pubkey, dTag: liveEvent.dTag, relays: relays).bech32string {
                        roomAddress = bech32
                    }
                }
                else {
                    let relaysForHint: [String] = Array(resolveRelayHint(forPubkey: liveEvent.pubkey))
                    if let bech32 = try? ShareableIdentifier(prefix: "naddr", kind: 30311, pubkey: liveEvent.pubkey, dTag: liveEvent.dTag, relays: relaysForHint).bech32string {
                        roomAddress = bech32
                    }
                }
                liveEvent.fetchPresenceFromRelays()
            }
            .background(.ultraThinMaterial)
            .preference(key: TabTitlePreferenceKey.self, value: liveEvent.title ?? "(Stream)")
            .withNavigationDestinations()
            .nbNavigationDestination(isPresented: $showZapSheet, destination: {
                if let zapCustomizerSheetInfo {
                    ZapCustomizerSheet(name: zapCustomizerSheetInfo.name, customZapId: zapCustomizerSheetInfo.customZapId, supportsZap: true)
                        .presentationDetentsLarge()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                        .onDisappear {
                            sendSatsToWhoShown = false
                        }
                }
            })
            .nbNavigationDestination(isPresented: $showNonNWCZapSheet, destination: {
                if let paymentInfo {
                    PaymentAmountSelector(paymentInfo: paymentInfo)
                        .presentationDetentsLarge()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                        .onDisappear {
                            sendSatsToWhoShown = false
                        }
                }
            })
            .sheet(item: $selectedContact) { nrContact in
                NBNavigationStack {
                    SelectedParticipantView(nrContact: nrContact, showZapButton: true, aTag: liveEvent.id, showModeratorControls: false, selectedContact: $selectedContact)
                    .environmentObject(themes)
                    .environmentObject(la)
                    .padding(10)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            if IS_CATALYST {
                                Button {
                                    selectedContact = nil
                                } label: {
                                    Image(systemName: "xmark")
                                       .imageScale(.large) // Adjust the size of the "X"
                                }
                            }
                        }
                    }
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
                .presentationDetents45ml()
            }
        }
        else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        Text(liveEvent.title ?? " ")
            .padding(.top, 5)
            .font(.title2)
            .fontWeightBold()
            .lineLimit(contentExpanded ? 3 : 1)
            .onTapGesture {
                withAnimation {
                    contentExpanded.toggle()
                }
            }
        
        if let summary = liveEvent.summary, (liveEvent.title ?? "") != summary && contentExpanded {
            Text(summary)
                .lineLimit(!toggleReadMore ? 2 : 200)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleReadMore.toggle()
                }
        }
        
        if let roomAddress, contentExpanded { // TODO: Move to toolbar dropdown for more chat space
            CopyableTextView(text: roomAddress, copyText: "nostr:" + roomAddress)
                .foregroundColor(Color.gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140)
        }
    }
    
    @ViewBuilder
    private var sendSatButton: some View {
        Button {
            guard isFullAccount() else { showReadOnlyMessage(); return }
            if satsReceivers.count == 1, let nrContact = satsReceivers.first {
                withAnimation {
                    sendSatsToWhoShown = true
                    contentExpanded = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    sendSats(nrContact: nrContact)
                }
            }
            else {
                withAnimation {
                    sendSatsToWhoShown = true
                    contentExpanded = false
                }
            }
        } label: {
            Image(systemName: "bolt.fill")
        }
        .buttonStyle(NosturButton())
    }
    
    @ViewBuilder
    private var sendSatsToWho: some View {
        if !satsReceivers.isEmpty {
            ScrollView(.horizontal) {
                HFlow(alignment: .top) {
                    ForEach(satsReceivers) { nrContact in
                            NestParticipantView(
                                nrContact: nrContact,
                                role: liveEvent.role(forPubkey: nrContact.pubkey),
                                aTag: liveEvent.id,
                                showControls: false
                            )
                            .onTapGesture {
                                sendSats(nrContact: nrContact)
                            }
                        .id(nrContact.pubkey)
                        .frame(width: 95, height: 95)
                        .fixedSize()
                    }
                }
                .frame(height: 100)
            }
        }
        else {
            themes.theme.listBackground.frame(height: 100)
        }
    }
    
    @State private var satsReceivers: [NRContact] = []
    
    @ViewBuilder
    private var participantsView: some View {
        
        // ON STAGE
        if !liveEvent.onStage.isEmpty {
            ScrollView(.horizontal) {
                HFlow(alignment: .top) {
                    ForEach(liveEvent.onStage.indices, id: \.self) { index in
                            NestParticipantView(
                                nrContact: liveEvent.onStage[index],
                                role: liveEvent.role(forPubkey: liveEvent.onStage[index].pubkey),
                                aTag: liveEvent.id,
                                showControls: liveEvent.liveKitConnectUrl != nil
                            )
                            .onTapGesture {
                                if liveEvent.onStage[index] == selectedContact {
                                    selectedContact = nil
                                }
                                else {
                                    selectedContact = liveEvent.onStage[index]
                                }
                            }
                        .id(liveEvent.onStage[index].pubkey)
                        .frame(width: 95, height: 95)
                        .fixedSize()
                    }
                }
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
                        .id(liveEvent.listeners[index].pubkey)
                        .frame(width: 95, height: 95)
                        .fixedSize()
                    }
                }
                .frame(height: 100)
            }
        }
    }
    
    @ViewBuilder
    private var videoStreamView: some View {
        if liveEvent.streamHasEnded, let recordingUrl = liveEvent.recordingUrl, let _ = URL(string: recordingUrl) {
            EmptyView()
        }
        else if liveEvent.streamHasEnded {
            EmptyView()
        }
        else if let url = liveEvent.url {
            if url.absoluteString.suffix(5) == ".m3u8" {
                EmptyView()
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
    
    private func sendSats(nrContact: NRContact) {
        if SettingsStore.shared.nwcReady {
            // Trigger custom zap
            sendNotification(.showZapCustomizerSheet, ZapCustomizerSheetInfo(name: nrContact.anyName, customZapId: "LIVE-\(nrContact.pubkey)", zapAtag: liveEvent.id))
        }
        else {
            nonNWCtap(nrContact: nrContact)
        }
    }
    
    @State private var isLoading = false
    
    private func nonNWCtap(nrContact: NRContact) {
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
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrContact.zapperPubkeys.insert(zapperPubkey)
                            }
                            // Old zap sheet
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrContact: nrContact, zapAtag: liveEvent.id, withPending: true)
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
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                nrContact.zapperPubkeys.insert(zapperPubkey)
                            }
                            let paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrContact: nrContact, zapAtag: liveEvent.id, withPending: true)
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
    
    private var shouldShowSatsButton: Bool {
        satsReceivers.count > 0
    }
}


@available(iOS 18.0, *)
#Preview("Detail stream") {
    
    PreviewContainer({ pe in
        pe.loadLiveEvent()
        pe.loadNoDBChats() // Why chats not loading here but are loading in other Preview?
        Task {
            if let liveEvent = PreviewFetcher.fetchEvent("44dffcfc35d8084c9d66bd2095f8392be726ed203e9458de1b643f4a381fff7c") {
                let nrLiveEvent = NRLiveEvent(event: liveEvent)
                await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: nrLiveEvent)
            }
        }
    }) {
        TabView {
            Text("Tab")
        }
        .overlay(alignment: .center) {
            OverlayPlayer()
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}

