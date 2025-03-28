//
//  ChatRoom.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/07/2024.
//

import SwiftUI
import NavigationBackport

struct ChatRoom: View {
        
    public let aTag: String
    public let theme: Theme
    public let anonymous: Bool
    @ObservedObject public var chatVM: ChatRoomViewModel
    public var zoomableId: String = "Default"

    @State private var message: String = ""
    @State private var account: CloudAccount? = nil
    @State private var timer: Timer?
    @State private var selectedContact: NRContact? = nil
    
    @Namespace private var bottom
    
    var body: some View {
#if DEBUG
let _ = Self._printChanges()
#endif
        ScrollViewReader { proxy in
            if let account {
                VStack(spacing: 0) {
                    List {
                        switch chatVM.state {
                            case .initializing:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .loading:
                                CenteredProgressView()
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .ready:
                                if chatVM.messages.isEmpty {
                                    VStack {
                                        Spacer()
                                        Text("Welcome to the chat")
                                        Spacer()
                                    }
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                                    .centered()
                                    .listRowInsets(.init())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                }
                                else {
                                    ForEach(chatVM.messages) { rowContent in
                                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                                            ChatRow(content: rowContent, theme: theme, zoomableId: zoomableId)
                                        }
                                        .padding(.vertical, 5)
                                        .scaleEffect(x: 1, y: -1, anchor: .center)
                                    }
                                    .listRowInsets(.init())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                }
                            case .timeout:
                                VStack {
                                    Text("timeout")
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(.init(Color.clear))
                                .scaleEffect(x: 1, y: -1, anchor: .center)
                            case .error(let string):
                                Text(string)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(.init(Color.clear))
                                    .scaleEffect(x: 1, y: -1, anchor: .center)
                        }
                    }
                    .scrollContentBackgroundHidden()
                    .listStyle(.plain)
                    .safeAreaScroll()
                    .scaleEffect(x: 1, y: -1, anchor: .center)
                    .padding(.top, 20)
                    .overlay(alignment: .topTrailing) {
                        if !chatVM.topZaps.isEmpty {
                            ChatTopZaps(messages: chatVM.topZaps)
                                .padding(.top, 50)
                                .padding(.trailing, 5)
                        }
                    }
                    .onChange(of: chatVM.state) { newValue in
                        if newValue == .ready {
                            proxy.scrollTo(bottom)
                        }
                    }
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                    }
                    .onAppear {
                        try? chatVM.start(aTag: aTag)
                    }
                    
                    if !anonymous {
                        HStack {
                            MiniPFP(pictureUrl: account.pictureUrl, size: 40.0)
                            ChatInputField(message: $message, startWithFocus: false, onSubmit: submitMessage)
                        }
                        .padding(.bottom, 15)
                    }
                }
            }
        }

        .onAppear {
            account = Nostur.account()
            startTimer()
        }
        .onDisappear {
            stopTimer()
            chatVM.closeLiveSubscription()
            chatVM.removeChatsFromExistingIdsCache()
        }
        
        
        
    }
    
    private func submitMessage() {
        // Create and send DM (via unpublisher?)
        guard let account = self.account, account.privateKey != nil else { AppSheetsModel.shared.readOnlySheetVisible = true; return }
        guard !message.isEmpty else { return }
        var nEvent = NEvent(content: message)
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        nEvent.kind = .chatMessage
        nEvent.tags.append(NostrTag(["a", aTag]))
        
        nEvent.publicKey = account.publicKey
        
        if account.isNC {
            nEvent = nEvent.withId()
            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                Unpublisher.shared.publishNow(signedEvent, skipDB: true)
                sendNotification(.receivedMessage, RelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
                bg().perform {
                    Importer.shared.existingIds[signedEvent.id] = EventState(status: .RECEIVED, relays: "self")
                }
            })
            
            message = ""
        }
        else {
            guard let signedEvent = try? account.signEvent(nEvent) else { return }
            Unpublisher.shared.publishNow(signedEvent, skipDB: true)
            sendNotification(.receivedMessage, RelayMessage(relays: "self", type: .EVENT, message: "", subscriptionId: "-DB-CHAT-", event: signedEvent))
            bg().perform {
                Importer.shared.existingIds[signedEvent.id] = EventState(status: .RECEIVED, relays: "self")
            }
            message = ""
        }
    }
    
    private func startTimer() { // Make sure real time sub for chat messages stays active
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            chatVM.updateLiveSubscription()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

@available(iOS 18.0, *)
#Preview("Empty chatroom") {
    @Previewable @StateObject var chatVM = ChatRoomViewModel()

    PreviewContainer {
        Box {
            ChatRoom(aTag: "30311:5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e:f65e7db0-8072-4073-9280-ecf15ae9fd52", theme: Themes.default.theme, anonymous: false, chatVM: chatVM)
                .environmentObject(ViewingContext(availableWidth: DIMENSIONS.shared.articleRowImageWidth(), fullWidthImages: false, theme: Themes.default.theme, viewType: .row))
        }
    }
}

@available(iOS 18.0, *)
#Preview("Chats and zaps") {
    @Previewable @StateObject var chatVM = ChatRoomViewModel()
    
    PreviewContainer({ pe in
        pe.loadLiveEvent()
        pe.loadNoDBChats()
    }){
        Box {
            ChatRoom(aTag: "30311:cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5:537a365c-f1ec-44ac-af10-22d14a7319fb", theme: Themes.default.theme, anonymous: false, chatVM: chatVM)
//                .padding(10)
                .environmentObject(ViewingContext(availableWidth: DIMENSIONS.shared.articleRowImageWidth(), fullWidthImages: false, theme: Themes.default.theme, viewType: .row))
        }
    }
}
