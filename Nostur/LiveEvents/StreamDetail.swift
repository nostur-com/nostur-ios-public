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
                                    .background(themes.theme.background)
                        }
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                        }
                        
                        ChatRoom(aTag: liveEvent.id, theme: themes.theme, anonymous: false, chatVM: liveEvent.chatVM)
                            .frame(minHeight: UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular ? 250 : 150, maxHeight: .infinity)
                            .padding(.horizontal, 5)
                            .padding(.bottom, 15)
                            .environmentObject(vc)
                        
                            .overlay(alignment: .top) {
                                VStack {
                                    headerView
                                        .frame(maxWidth: .infinity)
                                    
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
                                    Button {
                                        contentExpanded.toggle()
                                    } label: {
                                        Image(systemName: !contentExpanded ? "chevron.down" : "chevron.up")
                                            .padding()
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityHint(contentExpanded ? "Collapse" : "Expand")
                                    .buttonStyle(.plain)
                                }
                            }
                    }
                }
                .frame(minHeight: geo.size.height)
                .onAppear {
                    vc = ViewingContext(availableWidth: UIScreen.main.bounds.width - 10, fullWidthImages: false, theme: themes.theme, viewType: .row)
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
                            NRState.shared.draft = "\(liveEvent.title ?? "Watching") 👇\n\n" + "nostr:" + roomAddress
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
                liveEvent.fetchPresenceFromRelays()
            }
            .background(.ultraThinMaterial)
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
            .nbNavigationDestination(isPresented: $showNonNWCZapSheet, destination: {
                if let paymentInfo {
                    PaymentAmountSelector(paymentInfo: paymentInfo)
                        .environmentObject(NRState.shared)
                        .presentationDetentsLarge()
                        .environmentObject(themes)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                }
            })
            .sheet(item: $selectedContact) { nrContact in
                NBNavigationStack {
                    SelectedParticipantView(nrContact: nrContact, showZapButton: true, aTag: liveEvent.id, showModeratorControls: false, selectedContact: $selectedContact)
                    .environmentObject(themes)
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
                .presentationBackgroundCompat(themes.theme.background)
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
            .padding(10)
            .font(.title2)
            .fontWeightBold()
            .lineLimit(contentExpanded ? 3 : 1)
            .onTapGesture {
                contentExpanded.toggle()
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
                                aTag: liveEvent.id,
                                showControls: liveEvent.liveKitConnectUrl != nil
                            )
                            .onTapGesture {
//                                guard liveEvent.liveKitConnectUrl != nil else { return } // only for nests for now because navigation issues / video stream doesn't continue in bg
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
//                                guard liveEvent.liveKitConnectUrl != nil else { return } // only for nests for now because navigation issues / video stream doesn't continue in bg
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
            OverlayVideo()
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}

