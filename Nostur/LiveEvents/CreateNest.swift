//
//  CreateNest.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/09/2024.
//

import SwiftUI
import NavigationBackport

struct CreateNest: View {
    
    public let account: CloudAccount
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var server = "nostrnests.com"
    @State private var enableRecording = false
    
    @State private var selectedRelays: [String] = []
    
    @State private var creatingRoomState: CreateNestState = .initial
    @State private var backlog = Backlog(auto: true)
    
    @FocusState private var isTitleFocused: Bool // Declare focus state
    
    var body: some View {
        VStack(alignment: .leading) {
            TextField("Nest title", text: $title, prompt: Text("What do you want to talk about?"))
                .disabled(creatingRoomState != .initial)
                .lineLimit(3)
                .focused($isTitleFocused)
                .font(.title3)
                .fontWeightBold()
                .padding(.bottom, 30)
                .padding(.top, 30)
            
//            Toggle(isOn: $enableRecording) { // TODO: Implement
//                Text("Record audio")
//            }
//            .disabled(creatingRoomState != .initial)
//            .padding(.bottom, 30)
            
            Text("Nests server:")
                .padding(.top, 30)
                .fontWeightBold()
            TextField("Nests server", text: $server, prompt: Text("Nests Audio Server"))
                .disabled(creatingRoomState != .initial)
                .lineLimit(1)
                .padding(.bottom, 30)
            
//            Text("Nests will be announced on:") // TODO: Add back after we have some more option
//                .fontWeightBold()
//                .padding(.bottom, 10)
//            ForEach(selectedRelays.indices, id:\.self) { index in
//                Text(selectedRelays[index])
//                    .id(selectedRelays[index])
//                    .opacity(0.3)
//            }
            
            Spacer()
            
            switch creatingRoomState {
            case .initial:
                HStack {
                    Button {
                        startNest()
                    } label: {
                        HStack {
                            MiniPFP(pictureUrl: account.pictureUrl, size: 20.0)
                            Text("Start now")
                        }
                        .fontWeightBold()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NestButtonStyle(theme: Themes.default.theme, style: .borderedProminent))
                    .disabled(title.isEmpty)
                    .hCentered()
//                    Button {
//                        
//                    } label: {
//                        Image(systemName: "calendar.badge.clock")
//                            .fontWeightBold()
//                            .padding(.horizontal, 20)
//                            .padding(.vertical, 5)
//                            .contentShape(Rectangle())
//                    }
//                    .buttonStyle(NestButtonStyle(theme: Themes.default.theme))

                }
            case .creatingRoom:
                ProgressView()
                    .hCentered()
            case .created:
                EmptyView()
            case .error:
                Text("Error")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            isTitleFocused = true // Focus the TextField when view appears
            preselectRelays()
        }
    }
    
    private func startNest() {
        creatingRoomState = .creatingRoom
        // Create Room (NESTS API) (receive roomId / dTag)
        let service = "https://\(server)"
        Task { @MainActor in
            if let response: CreateRoomResponse = try? await createRoom(baseURL: service, account: account, relays: selectedRelays, hlsStream: false) {
                let streaming = "wss+livekit://\(server)"
                var nestsEvent = createNestsEvent(title: title, summary: "", service: service, streaming: streaming, starts: .now, relays: selectedRelays, roomId: response.roomId)
                
                let signedNestsEvent: NEvent
                
                if account.isNC {
                    // Sign remotely
                    nestsEvent = nestsEvent.withId()
                    signedNestsEvent = try await withCheckedThrowingContinuation { continuation in
                        NSecBunkerManager.shared.requestSignature(forEvent: nestsEvent, usingAccount: account) { signedEvent in
                            continuation.resume(returning: signedEvent)
                        }
                    }
                } else {
                    // Sign locally
                    guard let signedEvent = try? account.signEvent(nestsEvent) else {
                        creatingRoomState = .error
                        return
                    }
                    signedNestsEvent = signedEvent
                }
                
                let subId = UUID().uuidString
                
                let task = ReqTask(
                    prio: true,
                    subscriptionId: subId,
                    reqCommand: { (taskId) in
                        Unpublisher.shared.publishNow(signedNestsEvent, skipDB: true)
                        MessageParser.shared.handlePrioMessage(message: RelayMessage(relays: "local", type: .EVENT, message: "", subscriptionId: taskId, event: signedNestsEvent), nEvent: signedNestsEvent, relayUrl: "local")
                    },
                    processResponseCommand: { (taskId, _, event) in
                        bg().perform {
                            guard let event else { return }
                            let nrLiveEvent = NRLiveEvent(event: event)
                            Task { @MainActor in
                                guard let connectUrl = nrLiveEvent.liveKitConnectUrl else {
                                    creatingRoomState = .error
                                    return
                                }
                                LiveKitVoiceSession.shared.activeNest = nrLiveEvent
                                LiveKitVoiceSession.shared.connect(connectUrl, token: response.token, accountType: .account(account), nrLiveEvent: nrLiveEvent) {
                                    Task { @MainActor in
                                        nrLiveEvent.goLive(account: account)
                                        dismiss()
                                    }
                                }
                                
                            }
                        }
                        self.backlog.clear()
                    },
                    timeoutCommand: { _ in
                        creatingRoomState = .error
                    })

                backlog.add(task)
                task.fetch()
            }
            else {
                creatingRoomState = .error
            }
        }
    }
    
    private func preselectRelays() {
        let accountPubkey = account.publicKey
        // take own kind 10002 write relays
        bg().perform {
            if let kind10002 = Event.fetchReplacableEvent(10002, pubkey: accountPubkey, context: bg()) {
                let relays: [String] = kind10002.fastTags
                    .filter { tag in
                        tag.0 == "r"
                    }
                    .compactMap { tag in
                        guard tag.2 == nil || tag.2 == "write" else { return nil }
                        return normalizeRelayUrl(tag.1)
                    }
                
                Task { @MainActor in
                    self.selectedRelays = Array(Set(relays))
                }
            }
        }
        
        // else fall back to defaults
        if selectedRelays.isEmpty {
            selectedRelays = ["wss://nos.lol", "wss://relay.damus.io", "wss://relay.nostr.band", "wss://nostr.wine"]
        }
    }
}

enum CreateNestState {
    case initial
    case creatingRoom
    case created
    case error
}

func createNestsEvent(title: String, summary: String = "", service: String, streaming: String, starts: Date, status: String = "planned", relays: [String], roomId: String) -> NEvent {
    var nEvent = NEvent(content: "")
    nEvent.kind = .custom(30311)
    nEvent.tags = [
        NostrTag(["d", roomId]),
        NostrTag(["relays"] + relays),
        NostrTag(["service", service]),
        NostrTag(["streaming", streaming]),
        NostrTag(["starts", String(Int(starts.timeIntervalSince1970))]),
        NostrTag(["summary", ""]),
        NostrTag(["title", title]),
        NostrTag(["status", status])
    ]
    
    return nEvent
}

#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT", "relays", {"kind":10002,"id":"5a61af02a3cbc2aa539c7401fb3bb5a7c1c09b9c28744930435bdb23aeea0553","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1720046598,"tags":[["r","wss://nostr.wine"],["r","wss://nos.lol","write"],["r","wss://relay.damus.io","read"],["r","wss://fabian.nostr1.com"]],"content":"","sig":"5e9958948ad56659b8f21c1d28f48c3a6997848fb9675ec96880fb634352000efb9e9f71c14dd44d70c17634e6e18a98e1e0a7ef4d9ffad1d28e9bc71e472695"}]"###
        ])
    }) {
        CreateNestPreviewTest()
    }
}


struct CreateNestPreviewTest: View {
    
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        NBNavigationStack {
            CreateNest(account: la.account)
                .navigationTitle("Create your Audio Nest")
                .navigationBarTitleDisplayMode(.inline)
                .padding()
        }
    }
}
