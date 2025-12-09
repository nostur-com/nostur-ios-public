//
//  DMConversationColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/12/2025.
//

import SwiftUI
import NavigationBackport

struct DMConversationColumn: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    
    public let participantPs: Set<String>
    public let ourAccountPubkey: String
    @Binding var navPath: NBNavigationPath
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZStack {
            theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
            // FOLLOWING
            Text("Conversation for \(participantPs) - ourAccountPubkey: \(ourAccountPubkey) here")
        }
        .background(theme.listBackground)
    }
    
//    @ToolbarContentBuilder
//    private func newPostButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .picture(_) = config.columnType { // No settings for .picture
//                Button("Post New Photo", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .picture)
//                }
//            }
//            
//            if case .yak(_) = config.columnType { // No settings for .yak
//                Button("New Voice Message", systemImage: "square.and.pencil") {
//                    guard isFullAccount() else { showReadOnlyMessage(); return }
//                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .shortVoiceMessage)
//                }
//            }
//        }
//    }
//    
//    @ToolbarContentBuilder
//    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            if case .vine(_) = config.columnType { // No settings for .vine
//               
//            }
//            else { // Settings on every feed type except .vine
//                Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
//                    AppSheetsModel.shared.feedSettingsFeed = config.feed
//                }
//            }
//        }
//    }
}

struct DMConversationView17: View {
    private let participants: Set<String>
    private let ourAccountPubkey: String
    
    @StateObject private var vm: ConversionVM
    
    init(participants: Set<String>, ourAccountPubkey: String) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        _vm = StateObject(wrappedValue: ConversionVM(participants: participants, ourAccountPubkey: ourAccountPubkey))
    }
    
    var body: some View {
        Container {
            switch vm.viewState {
            case .initializing, .loading:
                ProgressView()
            case .ready(let nrChats):
                Text("nrChats here: \(nrChats.count)")
                LazyVStack {
                    ForEach(nrChats) { nrChat in
                        ChatMessageRow(nrChat: nrChat, zoomableId: "", selectedContact: .constant(nil))
                    }
                }
            case .timeout:
                Text("Unable to load conversation")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .task {
            await vm.load()
        }
        .environmentObject(ViewingContext(availableWidth: DIMENSIONS.articleRowImageWidth(UIScreen.main.bounds.width), fullWidthImages: false, viewType: .row))
    }
}

@available(iOS 17.0, * )
struct BalloonView17: View {
    public var isSentByCurrentUser: Bool
    public var time: String
    @ObservedObject public var nrChatMessage: NRChatMessage
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    var body: some View {
        HStack {
            if isSentByCurrentUser {
                Spacer()
            }
            
            DMContentRenderer(pubkey: nrChatMessage.pubkey, contentElements: nrChatMessage.contentElementsDetail, availableWidth: availableWidth, isSentByCurrentUser: isSentByCurrentUser)
//                    .debugDimensions("DMContentRenderer")
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSentByCurrentUser ? theme.accent : theme.background)
                )
                .background(alignment: isSentByCurrentUser ? .bottomTrailing : .bottomLeading) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(isSentByCurrentUser ? theme.accent : theme.background)
                        .scaleEffect(x: isSentByCurrentUser ? 1 : -1)
                        .rotationEffect(.degrees(isSentByCurrentUser ? 35 : -35))
                        .offset(x: isSentByCurrentUser ? 10 : -10, y: 0)
                        .font(.system(size: 25))
                }
                .padding(.horizontal, 10)
                .padding(isSentByCurrentUser ? .leading : .trailing, 50)
                .overlay(alignment: isSentByCurrentUser ? .bottomLeading : .bottomTrailing) {
                    Text(time)
                        .frame(alignment: isSentByCurrentUser ? .leading : .trailing)
                        .font(.footnote)
                        .foregroundColor(nrChatMessage.nEvent.kind == .legacyDirectMessage ? .secondary : .primary)
                        .padding(.bottom, 8)
                        .padding(isSentByCurrentUser ? .leading : .trailing, 5)
                }
            
            if !isSentByCurrentUser {
                Spacer()
            }
        }
    }
}

@available(iOS 17.0, *)
#Preview("New DM") {
    PreviewContainer({ pe in
        pe.parseEventJSON([
            ###"{"content": "Heb veel performance problemen met Nostur de laatste dagen, enig idee waar dat aan kan liggen?", "created_at": 1726123083, "id": "72cffcb18b0c2ccc12947e6788160c79cd8b28231c762124dee35068ea1a0a15", "kind": 14, "pubkey": "06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71", "tags": [["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]], "sig": "edad"}"###,
            ###"{"content":"Testing","created_at":1726126083,"id":"82cffcb18b0c2ccc12947e6788160c79cd8b28231c762124dee35068ea1a0a15","kind":14,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]], "sig": "uhh"}"###
        ])
    }) {
        NBNavigationStack {
            let participants: Set<String> = ["06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]
            let ourAccountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            
            DMConversationView17(participants: participants, ourAccountPubkey: ourAccountPubkey)
        }
    }
}
