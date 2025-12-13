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

@available(iOS 17.1, *)
struct DMConversationView17: View {
    @Environment(\.theme) private var theme
    private let participants: Set<String>
    private let ourAccountPubkey: String
    
    @StateObject private var vm: ConversionVM
    @State private var text = ""
    @State private var errorText: String? = nil
    @Namespace private var bottomAnchor
    
    init(participants: Set<String>, ourAccountPubkey: String) {
        self.participants = participants
        self.ourAccountPubkey = ourAccountPubkey
        _vm = StateObject(wrappedValue: ConversionVM(participants: participants, ourAccountPubkey: ourAccountPubkey))
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            theme.listBackground
            
            switch vm.viewState {
            case .initializing, .loading:
                ProgressView()
            case .ready(let days):
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack {
                            ForEach(days) { day in
                                DayView(ourAccountPubkey: ourAccountPubkey, day: day, balloonErrors: vm.balloonErrors, balloonSuccesses: vm.balloonSuccesses)
                            }
                            Color.clear
                                .frame(height: 0)
                                .id(bottomAnchor)
                        }
                    }
                    .defaultScrollAnchor(.bottom)
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                    }
                    .onAppear {
                        scrollProxy.scrollTo(bottomAnchor, anchor: .bottom)
                        vm.markAsRead()
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Group {
                        if vm.isAccepted {
                            ChatInputField(message: $text) {
                                Task { @MainActor in
                                    guard !text.isEmpty else { return }
                                    let textToSend = text
                                    do {
                                        errorText = nil
                                        text = ""
                                        try await vm.sendMessage(textToSend)
                                    }
                                    catch DMError.PrivateKeyMissing {
                                        AppSheetsModel.shared.readOnlySheetVisible = true
                                        text = textToSend
                                    }
                                    catch {
                                        errorText = "Could not send message"
                                        text = textToSend
                                    }
                                }
                            }
                        }
                        else {
                            Divider()
                            Button(String(localized:"Accept message request", comment:"Button to accept a Direct Message request")) {
                                vm.isAccepted = true
//                                DataProvider.shared().saveToDiskNow(.viewContext)
//                                DirectMessageViewModel.default.reloadAccepted()
                                
                            }
                            .buttonStyle(NRButtonStyle(style: .borderedProminent))
                        }
                    }
                    .padding(.vertical, 5)
                    .modifier {
                        if #available(iOS 26.0, *), IS_CATALYST {
                            $0.padding(.bottom, 50)
                        }
                        else {
                            $0
                        }
                    }
                    .background(theme.listBackground)
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
        .background(theme.listBackground)
        .navigationTitle("To: \(vm.receiverContacts.map { $0.anyName }.formatted(.list(type: .and)))")
        .task {
            await vm.load()
        }
        .environmentObject(ViewingContext(availableWidth: DIMENSIONS.articleRowImageWidth(UIScreen.main.bounds.width), fullWidthImages: false, viewType: .row))
    }
}

struct DayView: View {
    public let ourAccountPubkey: String
    @ObservedObject public var day: ConversationDay
    public let balloonErrors: [BalloonError]
    public let balloonSuccesses: [BalloonSuccess]
    
    var body: some View {
        // day header
        Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .fontWeightBold()
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
        
        // messagess
        ForEach(day.messages) { message in
//                            ChatMessageRow(nrChat: message, zoomableId: "", selectedContact: .constant(nil))
            BalloonView17(nrChatMessage: message, accountPubkey: ourAccountPubkey)
                .overlay(alignment: .bottom) {
                    HStack {
                        ForEach(self.balloonSuccesses.filter { $0.messageId == message.id }) { success in
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.green)
                                .infoText("Succesfully sent to \(success.receiverPubkey)'s relay: \(success.relay)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        ForEach(self.balloonErrors.filter { $0.messageId == message.id }) { error in
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red)
                                .infoText("\(error.relay): \(error.errorText)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            
        }
    }
}

struct BalloonView17: View {
    @ObservedObject public var nrChatMessage: NRChatMessage
    public var accountPubkey: String
    
    
    private var isSentByCurrentUser: Bool {
        nrChatMessage.pubkey == accountPubkey
    }
    
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
                    Text(nrChatMessage.createdAt, format: .dateTime.hour().minute())
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

@available(iOS 17.1, *)
#Preview("New DM") {
    PreviewContainer({ pe in
        pe.parseEventJSON([
            ###"{"kind":4,"id":"fff8c33ce14af29921a6d737e6fe7f4be7eb6689f8c22468111fc4b813c7f6ee","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1732966153,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"cywUqdpmxTx7ycOlwREYWHNRPVrmcFHHwANXsO0Hx9j7UaTIsDoyNjjP/N75xz7A?iv=vZR3gyFrDniX3o3K+wOWkQ==","sig":"0a1da8058667aaf501a2fa0ca61f506ee0f9f849d94dbb7355d75956baa62b991333fb3c9d1be46e47613ef76bf1aff5a352a34ae88a47f543faa1f21d5d3bed"}"###,
            ###"{"kind":4,"id":"e312afd6dd189781241756d54f6d42cc69c3a7294a53694fffa5b8eab0880e31","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1731589700,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"u7MAvwej5IgHk1FDNCU0cfT51mbvwMFV+/9pm7dqOktl/bdPOtFxxiShc9IMgICwFYacy/xAVhnwWYsJDkVDWMp4o5tEBryVJC+QxOg5FS9PGhQeDuXod8KhRy9PDdJJmp6hzC4mknM8300z3F2JSDRvlcxZUELi+SQU+KrTG8Q=?iv=jILVmN/7+N5r1dSRO4bJNw==","sig":"48f95e8f36dbf46b979ceb48a3580c16185da1b815ce6a6aff98559d47722af4aaab258364ab55da9e9f2efd7fc98865dd89ad946290574b3e6e24b44dc29f80"}"###,
            ###"{"kind":4,"id":"90c07203a6bfa41f193b889331d5b91c09ae5de2226225bd09b58e0d7be60c62","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1731494836,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"hWZl/VIYA46DHolp7og7i3U7dcjsIZhIFX5Y5jCU1tZPtLrTL631M9baMXFP9NCAxJtbUuCKle6453e6lGSEyQ==?iv=JSt16hH42qil35u+Jo8J2A==","sig":"6d9c279d7d87506d4daf703171afa2732bf5dadb700ede3809a0bf2cda2eeb14f069422c2e34c104790c3895cd4e34017d08658aa1c436f2297c9adb8189bc76"}"###,
            ###"{"kind":4,"id":"64bde7361d4adbce83afaa4b9aac41409b6fa7a9dccde935a39bbdbb6d911f39","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726733666,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"rO/pgiY9sB/cM3E4CLCzzKzGrCSPJ6SmeDzId6YbpqJzMaqSX8NCo6bbhwWA6xSGmpwOL/orShVqwoFPwl4qGw==?iv=UO82krEqhdpF8lCYZ3TgHg==","sig":"e8eaa2dc1bcd67b3f66d41c84d38b5f9ff1ebf68403cc5fcca32489bf2c7cd5c3096fd9729227d8ae138d8e324a25eaeb58b6ab8ee8d6e1cd1952bcdb9e0f46a"}"###,
            ###"{"kind":4,"id":"6b0a1cc1a7a85666580d5948daac8eb66b50339d3764547660a5834f2fdd489c","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726728346,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"RcxDWJP9MBtqXgC1zFmZSo6SZwVRBrhqZp39d0DDW0he6wDoTuO0OtkhOTYbHIoBKRw0nFaMal+fF3Bt/QRkqw==?iv=9qI7fab6RCr/cCu0lByu+Q==","sig":"384e408079bd332e24400fb35f3b08aa65f2820e95ea0a911878d31faa004465fc9ae4d35f1338e831ce36ae40ec0f4ffbc544c1e2f508dd649905298b2f3306"}"###,
            ###"{"kind":4,"id":"1e30be6e1989caf919cb8147c83295994fa0f5d7b04bb3692814517124af38df","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726728296,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"SpF6TUGB2j0JvCSdcwhkNY9vK05PBmd6tZHnCNohaCMEpCX80bbAYE6CjExIMFdSQamjQwTmxLu6o0kb2mUqjw+YbMPdo95o9twfLmfXlDEgcNYtMjSCSvShMnZiUpd1InhYuCJq83Pq1kp/fvtrKA==?iv=saWVTwkG+t7EBS42gniqtQ==","sig":"4e7863e4bfcf7c344c2fda0b6ebc99b767c34e09125e531a2e34fb44801e3b8784137edd0baca1d7b177b98162a8083df1d8a05dc1eca5281d6fb53ab352861e"}"###,
            ###"{"kind":4,"id":"3b71f8367a2103ff95ecb790c835428bf8320506b45ebf360e39fa1f9d47838d","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726728260,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"rzCme1arg6mlhvixjpdTp5abOBuQnRQmde7b1LMmV+za+J/0le+KQ4tviOrCOQe2?iv=bcWHgIpcZBSnOX7BxWlOPQ==","sig":"e21486ab90c6482ad98211714c3fc8c6766ffa7b02cbdbceb9b715d658d6415d7a862af43068237fb48b8a7afeeb37acd40da474fe832f1fdd4511a8b272aafa"}"###,
            ###"{"kind":4,"id":"af89a85eb8170779ff3fc6ac0c9f6816bf66e1677f8aebef9bfd2d748f952c27","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726727715,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"KbkLIODjVFopll1nzLxKAHJP+xdS32hbIBZE2HdEGgzHND8uJFmsQV4dKPWoc4HC?iv=a/KcpFS+//IXURxFdlF03g==","sig":"2b35c14b8a25aa8735b6406e9e36c8eba30e0c496353b41c057fcd29f4faa9075051cfe95c5924c6d031f8d29e3b1b2a53aab4c199e1d1c06da7061f9cef46fc"}"###,
            ###"{"kind":4,"id":"9d896001d1abf1b05df25e079b0479bc8ec7c235ece10cf6836802a57da29c37","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726727686,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"jb1eZ0SQNoTnfHNCST7yMbss6+Eyj6QPA31kMUFYcr0=?iv=0mtdCsc/WNLz2o8u76bw9Q==","sig":"52cd8839f2e41d80cfa5f22f1739244f6c3288d474d10d276d0bbf355e03ff7a609c72224c4af5044126c8b90be0854e22d7f0b884f6026a96d2a934076ad20d"}"###,
            ###"{"kind":4,"id":"7ee7ea4229d73624a41a5be4ede80842abb6d04ea508cdc39a16d2b911e7f99c","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726727675,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"KvP7pUB4XML7o4cOtX4qp1ujkd+nTa88JIO8ptXVjD4G8GWQnGGguHof5ZOmVbWk7hpn/1r5X+POcxH31YpWkh0INilR1EY+9oJVJme8eIv9Nd2XTWoUzC5XvVT11b99hkFKQcJY7aF+U4jloDcAAw==?iv=YOoM4ihrSB7tvjxfLGulLQ==","sig":"baff93fe86c797944c9253ed28812ef9627b906f64d44552f82f228c0796d4010d79b928cea1d75b196ee4dcc0b656c9cd77476686727093833ae87c20b85aee"}"###,
            ###"{"kind":4,"id":"9e91f75593f0fb8a11793c4457f98af628232d82b3610b4a52fdc494fb03ea81","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1726727581,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"z39jwxZziK+kzReI146h150yGjzQrwQ2cbg0YYyuYFc5RaDcg7CPfAKyd5nUNUXvd5sTNmFUBc5/+OsSezUndg==?iv=CYWMNDeGvrlSjWtNtMvn6w==","sig":"69310e8d9860cee1fd5567ab5a7a9c4bfb7a74a160d3d03930e1abe869680f17628d0f305c02b7002155f7a29a6d716e5ba9b5773a4dfbfc14c3667a36c47e10"}"###,
            ###"{"kind":4,"id":"b7f6380befae55f41e0d32148d9313f11d7b4aeced3e391a23da86578793e778","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1718529578,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"wble5UlnFk/uTOgHT52JQ0vLkNj33PZ7d05fU8U+fd094A3KWAGVrUj8+FgY0J+MB04FKE0FmYf5s7Ec7EDf025YYok9HN4m/mo5TwGP66bLknXfqIYKqK2lT/GEDlEim6CKm6cWtUhVFqXm7wyEgFQ0+wgvlkum8PBEZYJmAkA07RBbnq2ysmfouWhTdnNRUv6E4lWhfrvHF+4TZ8VsPHswQ0U0m5ryj55uQNAiHucCkQUVz9O2lnrctZBLC6NrZVH2pdrV+1V/LMMSe8y/d+fKFbx3KJg6KAZ+zNIQB8qVXVkIcQKVuGB+8sYyrSxaW7HZvbWlivm14cu3H5Z25A==?iv=WcZM+84gdtT9NV4Bm7j4Rw==","sig":"91b0e162bb3400fe169685b447e3cb6a31c48da83baa0a9fa2ee3cdd25efefff324e29201ac961e296a25fc700411bf657bec7fe1ad4c20b6071d8c249ec7efe"}"###,
            ###"{"kind":4,"id":"95260561c2cb6db38104e31c461501e762feb2d309c3c35187c28f29b19b9de6","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1718529440,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"B4D/jiDg5mpXzM4Tp6xCgCDELOf4fwnzx545Pc/hPBg=?iv=GnZq2XqLuY+C9qbLL4DfZw==","sig":"be4853c437b86159560b6353a496885da42e0ea0a20a25a50d10dca9b8a08d34d25f08a110d45e9a6f650f07914a561560194c85d024749e67c67d7f6321ce0a"}"###,
            ###"{"kind":4,"id":"cc58433330fdf481c8cf1b42671605b12b1d83134343528aae5d00a5a9df4c31","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1718274573,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"FJ0mOGPTLIsLJyh3qc8GGJmsxK5oVBGZgRuHjDkDhiPzWPpekzsoXkWGk73HARl/r0fuBruEgD7Ced+fv0YsqvOpiPzCwBfL2+XD0J/CjiiWHeKpUs62n5H+tFDOxf28w8rbvAit/cTEbs4xaZz10w==?iv=Tn/9jIo8tU9Q9+ttI7z4OA==","sig":"2ce76511b63ee9e3279c0fc6aa7a1d492acc13263b86fe00f7c6898ecea61ca2d4f976c93082605f52f1f3f7730c81865b3d2e8ee61f07571b96faf9946b0db7"}"###,
            ###"{"kind":4,"id":"bebe1545dd2b1ef882846a4d3dd5bd99e279e83c1e326f07b6c3368958fac9dd","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1717581791,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"dFWIIhzexGKdeY0haxURIcHIyeWipXCSn8R4SJxjAIg7D0uS48AV5A4tQcqLOdK3j61phTvk5ZfFWMno2TLcF6pvAwn/RyCUjB1vZFfNR6JhYP+2lp5qLmgR1HAPft1w9/li6GgDkhDwmM+gKq1X0Q==?iv=fBTiMa7ZmhiPdeQpJ4jlfg==","sig":"e2ebb39fc1376cdc333e471ae4d9c84d90ae621e97d53905bc84dfaabe110cf42b18a3d70e8fa5bf70430d44bf44145f75e35b394813731ba278bb42b1934ad7"}"###,
            ###"{"kind":4,"id":"72dad6ea2a9cf1b3b121d08730998a7540d0d99cd236e78d4851a66e2df5eee7","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1717498700,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"/PqN13Ky1K0BQKHX6k7YHDeJHpE2/qEwxI3MYMI6wKeDsrZ30YHijINNPYItRPovagDmOKIOiV2coQ8OkhDWogAouRcvSS/GJ24B+yr7PnflLwIYuoeQ2YNF0lQ36mdUQ7mF34+/zOet5jl05Os+Jg==?iv=c6i7pp0FzsXiBs0AKyjIbA==","sig":"e2625ad66f5b589e3a3a35c6d296e9a60741ab7d569f392f10c72ce8d2585c449182f877a538e5e2bc6a290b3f44c995ea8258d7df4a6b99e43235fd1a48dde7"}"###,
            ###"{"kind":4,"id":"b7bc2be4682482a3787254fdb97f162e112743e16ca8d08704a55d94ce23b707","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1717450903,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"A3TmRyTKSR4fZiq/eZHaL8p+PNaj2NmK7y7ECPFz3P4+F7g4HpIrmFkp7vt5bqkS?iv=aRvHXRDydpTaV67tBTYw7w==","sig":"03fbfff710c7f40271729a2e7ff51adcc37afca109cda10cc032b45be392840fd64933bda2eb03a1ed8f863ce1741de8b9a41b85bbf8b56084dcfba7babaa001"}"###,
            ###"{"kind":4,"id":"e73e7834b0b7b97aac30282419c5fa31a926aca41c4af029960bc94ca6657c81","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1709733246,"tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]],"content":"a5K/EXJLaLRwMs90UznCfY4/9s5ovZ/80zCGM0XIucm1kEaXNhAwlEGXXbFeO8eRDV/SMtMqefxKymuTu27Wehp2e9yofOcGnRw8VCOhqv0deOjiQ1ss+jJ6CdBzYKlCjPy1M8UcaxcB+xdRdRiWit9lFvreqzWcEqfrhZTmZt+JSEKofYbnwSW12zCBPSpqAdCyY1jMZxgFQ2CU3dCj2A==?iv=W99NB3oQYM+AMFRQFf2wCw==","sig":"1285c860b7137cec4bb9d236ed3d25f108103efd9e8494429bd1857de3a2ad1d58d3c6f7e00584af12a6880edcf83b7606b0e1be8945dcd36f34ae127f49b12f"}"###,
            ###"{"kind":4,"id":"7459488306c7d5d642890b1edd4690081068f240e27ba6b8fbe7deb569b5ac51","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1738654824,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"uzNiZGBr3Ok8qAm73K0tlg==?iv=nijjR1pCVA3iJSq3PgtKOA==","sig":"463d23a439211d95259381c273099e5d66df7c1302b059812a2a0bc75ff8f68a427a17630ada6631a8c32e6f60892d7e45e86c67fc1a93e031c9b82cf546ebb3"}"###,
            ###"{"kind":4,"id":"05897a384eeee118215e21c29e8a4edd8fe986c67f8cd27c882c2dc0f8781bfb","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1738654857,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"SKvZTcwBHV9RRYjGp6MqO/Jdz/KXWiFRjdVE0DeiIi/+6mXW6iaQo+D7NDpjY/Q4WDsJMp8P2G/KyFHRGBcwkepDK5TJpMT53YWMA5NWwoGzBbP7mN1pkU+O4LKtiL7iD0fCf9AEIJGhw8srNszmyA==?iv=BicD87HfxJ+BqrViAbpfMQ==","sig":"fe6fd9a6bb0b9c65ab8d782eeff835046f516e04422843a4b46b1a9833b5373210ae243217396cd80981d629b7adccf9b333948af9d10e6386933dbbcbdfb4a2"}"###,
            ###"{"kind":4,"id":"a79a4148ef6a7d1633a450c1982e01579bd1d254c128e85b8db2d2852d4945d2","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1738654823,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"3kO1f8HnQoPYqwWHyvoCrstSvpGTPjfmiL+bM3p+OQGWEEp9XB8Mxytefa4W7yyOW7XFoa0Ja65dXIYrzAd2GHeNTEKgEmlDV0GQgmwKkJBHBwb/1az+ucloKUDFwFIFWBoGQvTs5Eobibf5Hn/Bog==?iv=HUFFHP/QpeDojkxXg3Rz0A==","sig":"040ec05c223d6be505650d85915875cca1605790452961b7a4239d1491c08ee7d98ce8e6389aa9ef57d90552d5524ef81b36162063a0db99875831f5b6d62767"}"###,
            ###"{"kind":4,"id":"69425d16a5023da0298b5c4397b97403814335e3b9227f7f46d1b6fcf3db1e76","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1738654818,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"/mE0zQBZKi0z42dbETK9M8s+vCnxudXUsPVA5InKlKt9J3YlzdkacZPxfM5ChoC7?iv=DoXXvCRBVNGebykqudai0Q==","sig":"862d3e01ce9ef3c8c578d7f59867712c5c86f6902b42e903266d9230fe4c2e2223335420716eef89098ebc9b6362f98a0809bcc43493b510c505aee24e17d304"}"###,
            ###"{"kind":4,"id":"3ce394c7acb53d423b9dd0caee7b27ca2a30951a248651663b90f17b5f91bc2a","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1732971923,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"bDOmoh6z5cIbIaHDZmMdk+s/G+4ZSQgtQnkFk1SnQEn2WBYfb1SGQWtfvDg4ARHP4TRYd+czWOkYyWnUUncrkg==?iv=PJNSf4VJSz7Pro2vgXcoGw==","sig":"56aa7446d63c76c18f5a8207c13011a07fd514c5d4b571445e26bdb0942ec531c8ac5e064ccfb46974be3fa43fdc5dc34a716d2b894e0395a7a8a607cb8f6136"}"###,
            ###"{"kind":4,"id":"0e668820bd33bfb841f72ab9ef7b3dff756f45f921328f5628db9404509eb7cd","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1732971894,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"Wiak61ysLDgL09nxypLkazigRaGPsa0BB9DzVya0phUO238b7ttyLtYTRNwwbmSKv6VVZUjA90VN3rhxI+BTegRe91h3dKs1t9qlvTjuKO/mADWuZ5yjLR7FJ+7i0YLr?iv=uSDVAgNDgXxsANXD8B5mfg==","sig":"81cb7b51bc1f12df93a52cdb5e1c0e06ba0c8324a4b91fbba3b1281d021da8e84f5596f7b8f888f6ae4eaf9de7c5bfa2a7f4c6295a180ae1905609d0efcd25b9"}"###,
            ###"{"kind":4,"id":"fb0d6737a598e002b191d277781450347ef8347994632e19b447757f7a01ccce","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1732971871,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"/Djp995HQOGns/2wpdKoEQ==?iv=qDdgelFxdkGuq7Ac3oQYdA==","sig":"5e65f8a139991d6705a9ba8e4714dc7877d40334c45c65b51cec959906ec39b58503bb6e3072d5f4ff192bf91ca7c30ac6f5047fc9b3a10e296706db08bab040"}"###,
            ###"{"kind":4,"id":"fe0626db6101b820f3193d671bfce408ee325419c6b817ef1fe2bea30ddf0339","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1732906324,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"uW8phg5OdcR8FI4OscMKeqwgthQJRh0HyX20HI1KeUY6AffFa4POZ4n5amn7AiWu?iv=ltLvkgfD7uf3f9OlY13qeQ==","sig":"4179fe5bf3041cd53cc5814202f217e0aae2419e1beb29cad7b897348255276151e6d5813533cc2efaec7044549a4f3d50657f1acd133a51a474f6f185632002"}"###,
            ###"{"kind":4,"id":"3f8582110ed3ef03a108d042ec4f320059f1b7585f84a10cf4f0a09f1bb81812","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1732906294,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"ICDGVH3Jy3/ZX0LAPprPKA==?iv=Gk0OIUWNBTddPTP5rohR/w==","sig":"7d6556db83a37ddce41531b5195548671df115b2c599a61b740d4faf43a6606e5d25f8c5cc1e0ed6fab41679f8ee7c696dd516e8bdd9c68853f4404078df6ba8"}"###,
            ###"{"kind":4,"id":"5bf1db57dd9aefc3ce16b389799dc57393c2b346c0c587a4d60b29161d480194","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1731773369,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"1vM9/G81fIbU/35N3+yvrQPNu/VLmPijUHFmWTgekCxWj7oDFzdsiqu8sdWdr0yxjJRR6rpG8/qDD71jowhW+g==?iv=nTVSHBGkQSaorEsZaVrBFg==","sig":"79091578be1f50fed79a08d994ac0a5bc075201cf48e3af1d00d4801222bad204816b3df905b9a499cb673f91b8425ebbddfa2708f4574b6e191cca2f2ae4a74"}"###,
            ###"{"kind":4,"id":"589ace3d83e23d27da1cf1218eb337a50a7ec71a81fb9d4a523d9fde4aec2be9","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1731495752,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"HkheHQX2wzvUT3gtCbtdy4HYZgZxMdCFtySSunm9hsC1BluFQ5ibYhY/4QGAB3VtvSSm7YP89dCUAEz8VqFF3Q==?iv=qVauTF4uQAGP1AxDjAb4QQ==","sig":"1ae4ee6f93609a86e135bd92961218ac6fba428a3428c111cf027ecf545d6bfe068c90396cb4fc2dd86b6b92cfeef64c336c975d53d1017629cad814fc9fdec6"}"###,
            ###"{"kind":4,"id":"86aaf7bacf87c107332387e7ebe076e71acc5fe1835fb45f8ce3890e0d76fdcd","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1731495740,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"nhZ3toduZDbAmitTEJ84CtsTkSnTRBzXrTfk7xTcOCXVyRQtO9X6u2nLF2HTzX87?iv=Od7nmiU9qGKFzMo/TPL1Kg==","sig":"aaecb00a481a3a9686564dc0081011d5178118140fc33b624a557e1a74e9fc6268cf0782cba4c085c57532ce3cb719da2291b672a62ed79563d55f8c05268c5d"}"###,
            ###"{"kind":4,"id":"a23fdb2b6dee96f59c1d27474b3b435fe5a0c8ea40c538306fb60a42fa659201","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1731481308,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"TFF6McjJZABurat/kjMeaC5BHWHso3+1JfU3/bLlrpkaSAWJWwRppIvtDqC2y+tz?iv=ZKXv+r13x6wY7OOvrjyRlw==","sig":"19e6694c312afce6715df71f8a820026c45451269ab99916c1e6092572804c2fb78488e597c58c9139ef26ef3babfa9e72993f53db9df05ba3169a9f92446538"}"###,
            ###"{"kind":4,"id":"9ce9f024c693af0f553ff0b3ee8105fa1feb55ef47cd399f53a46f119834fd9b","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1731481291,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"aI1+NpiYVUAyRY1+7LngVtoTZAfRZw1sgmZZqt4MXri4fjr7eIk4cbjHkNTtAlAxxl8MW1VCRaGjfXPgqZoe/9q66ONttWKm0UJ78sTdJXjzaQ/Ywjwgr4cujozMPMQ+IDTRAlbM/nkf4NmQV6iVaw==?iv=mZt7nd/mUgCsQl2Zwqn/hQ==","sig":"6aa8c18efa7bc4de5a0becb0977ec7688cab4eedba4e4ae7273cea8781a730c472044eaaab918b7315909f617f8164a5ed91b6c468517f2ad44a9a77d207e3ae"}"###,
            ###"{"kind":4,"id":"3c9b4eaa50935b6f36636b0ec0e253845c5ac2e2e8f56e99baecfa200839ed60","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726769895,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"/b0SQZ13w+pmh5/hUVkeBVETP09RGfN7xxKkDcxnPXQ=?iv=a404frJBYPplD91ew3x9Jw==","sig":"0d3d1fe2ce0cc259063d5f7874325d2734b2dc5ffd36d62167232be787895c1ebdac456c2b1d02ae661c034c3dfab3e93d9773e999bbf622786ecfdb56c0522a"}"###,
            ###"{"kind":4,"id":"7ec72da4cd9bf356096898e9d5b4065c7f05370449161d8a6996137afc815eba","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726729573,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"PN0w0s1Ydv3zCNl81TjsrYt/MewwA4NTwJk3sxTIqdAgj0FXy3ygg6YWtsvfT5kGo3dOYIbgPKvAR9pPe7Ro2d9yEd2hLISlVQyZ0ldJn94m9s06RG0y0Y2IspINhKGPiw85qdWdqclI3vbipHUHK336dwML2Qyayn6A0sP0poRuYvmHmzYphlqEcEWMOcU5w2TN0+MGc1pkmzmpC/07nuHwlf9+32yZJFgIONa4FGkNHw4L/SXx8F0H++VXNMwc?iv=tqaq6/qvNwc1L6k/Bxe7YA==","sig":"f06101b764bbad9f1c00cf1335f77b925e97878d9585a7ffa13a261b2bb9130e1728906a9c8e7ce37cbf05df03ae7dc7b1ec973e8d82513ef97fce87a2ad42e6"}"###,
            ###"{"kind":4,"id":"0ffd330f4eac4b2747ca37ba50deac6e52618c94dfe715f1e0bdc613012c4bc1","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726728441,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"3jJnYLeIypBb5JvpD4n66ecD3P/brX+grTLN/2bjheYwjIqoC+z8Kq2pOkSj8pI7?iv=NcJeyvfQKXYwUIkL3WbPMQ==","sig":"e2b8830815a9c7938d9400e4b43a53c2cf7d5e2c6289d94cd23b5711084e63a5b0b40f8b503fe3d74216ac595755fac113e2d75d08006d250ab937e5a4f09891"}"###,
            ###"{"kind":4,"id":"b6d15df5480772a99a24e8afe79046e10b073ceb482ca15d91c0fd24d749e367","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726728403,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"paBM1EWvuOWmO6QifCF2XL/YWIM7nOqpu1zNQRSjTHXeXncf0EsiKbiFd4/jsUBhOJdqAosuaAiiVt1LecpshDQeCgMmSWZ7AjZJ6wBbnsU=?iv=hs9yU/ONORzkieyBjo1IwQ==","sig":"e80d9cd68641e0a8f1fca6de97ae5db4278875b10c9ea57252b216da8ea05f8b979a1d1a8babff930b12f0163c637725362ded426775fe0d27519348a36cef90"}"###,
            ###"{"kind":4,"id":"81dbd1743d47c478cf2286ff56a30a2d9ac738b5acbe75b663ae698618fc6ee3","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726728372,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"QKE3gB6o+V5MTH7qOhX09kvY19sswV/7wnQ/uJUecEo=?iv=fewj+/mtXt8ipDiK9JzwMw==","sig":"65e76404f21c6e700914c8e29357b4c6cc543b1045e56320ee01f8ea97f52bc0f5b2cebb45089a85af0620354c50944bb7d4d90d28dad7455ec01b87f7fef11a"}"###,
            ###"{"kind":4,"id":"883b2027e89f9d410edd4b7ec17cc10f6c7e637c662087ce4eda1c882ee9d6d5","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726728367,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"HQQwdGSDsycaDJ2O8kru6Q==?iv=dlvqAZQ5AUirOHxBuUkqGg==","sig":"5e991d92fabe4b29f0a2b267298e8bcaf54449c32c96ebd20cf89d0af55165580ce941b83e95ea1ef564523136dabdb1042e8d3160a5135e77fa3f783af1049c"}"###,
            ###"{"kind":4,"id":"a35582489b833899ce44918345b1f2eb481c13d9028a6179151b23ce88f57117","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726728075,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"IPTT7Vv03NV2JmPiu1w4yfPFnAS+NESl9R2EjMiyu8KgTQB3xqUR9tzAvHrEZ7LOxnoZHtwS50ARoY6TbfxHW93Sl5nUzNKBh9EAXpNh2t8=?iv=pelNcijy9ktW4S0C3zK3fw==","sig":"a33c6fb5c9b594cc7ee6d950bd522fefe68ed3b54da8cbc7d6805db130605f355a9d269ce6adbb8c1728290512d8c2ee6ff47664baa4cf1d6a8ea6cbabfb6bf0"}"###,
            ###"{"kind":4,"id":"5bdb678bf252de3e17064fc7b21456fee6e0cd13396ca27aefea3cbb6d96939f","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726727960,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"UtbAixWVQ/98ja8SVaJ3oT43bbo+xJSJlUNyJ8jY7xprPyrneUHBZv4tThle4Dyo?iv=P22aNKkSDeyQxpiF7IWIlQ==","sig":"2bd43b478ce8e987ee63897e1ca53ff164b2c02e062db51cc2b56da7f68e07c7020e043122e8eb06716c1873c67a29e1f7178cd69766fd61671ba56e6cb7942a"}"###,
            ###"{"kind":4,"id":"20976187e109deb58b8b3de505c9467f27ddb8f377b74deaad92d4aa01b2d2ee","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726725283,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"BuK1cX/bQod3Bp6nxE8YlPCtPRH7c/EXtG8Tb/qr0gAymxFNgGhNpd/qXnizOStX?iv=Vq2kc7ZIM5++xrjMLO00jA==","sig":"44ac3f9676f843ed49f121cf4618fbf058cafc21d9e5b24e9e3a76215eeff1b64a8bf5b22df8ca809c14df01fc1965b377b03b9ae6aec0caaac633e826ac9728"}"###,
            ###"{"kind":4,"id":"3bcb65a761169207a89d2b405b2cc7712d0c0fb0776b1ba46b420e36014a1958","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726725242,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"mfMRjFNpe33nwffJrxYtwQosvS7LUVXhEKSJxYDx5N/MwS0U/sOlk/tZfsWoVPK0X6HuDYBknSOkFfZTFHiqGOodgM6EYTpFdZA3jjHpavZGzd2YFlS9j9mK/VPBfCfB?iv=MGuA38MUmkfLQAGHrVW99A==","sig":"4f6bade5b0fc8c383fca4d94e84030d3867a2663940ff70f68a3cda672e1960386bb557b90cdc6cdf7db08bcaacdde93ca6a97c3bb9c608007b0a54fe1f25a65"}"###,
            ###"{"kind":4,"id":"72d5be537f53039e143be8b37d9cada05160b63b946e80cd2183f33d2c850bc8","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1726725206,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"iUEISPxjyi+FZ2fzrw2AP+6GTCtIZ2HfIjnd3jaY8IFAyEAcwlcNvy3ISQYwxUH+?iv=664u14x5OCX3bzGXoirhhw==","sig":"c35655e1bdae428ca995c89ba8ff5ed6653b64a298f1c73edc7cb9a8236d0e0d296bc72abce5c2ae9a9b48887e9a3bb1a1aea45e955b3c2fe7487d7f3a7d633f"}"###,
            ###"{"kind":4,"id":"f4a4cb04b54d8c7babb5d004c51cccd62a033e3dc9b207bc5bbe433f882ebacd","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718684837,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"iclj5vm82E2He8gRGzK/UIzIS1QnlV6KPdNKvgs9FCKVWqtAAYPLuSJRLWobA/pyukmuwZSG7hXaZoEJfb4d8GCuY9WvjqPxQMR9Az2TVkYQBsaYJZBLoeEEWgt1RIZv?iv=CztA1KXvFwSnUmAADj8D+g==","sig":"f4884f6335ba09b45cd71cabf871e6e11451c81c760d3f4c31375c144cbe08d07f1231a966c518d8cf133bc0aabf689ecbb1a35cdc2f6147e5e61fe7f13d1272"}"###,
            ###"{"kind":4,"id":"c51f8f17410a3075673cd3a16e5aee8779ab2fd5859f06d5a5b2319d9e26b891","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718684778,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"Lxxx6w5GwKcap2Nk0XOjG1SetyZ8/RUCgf9BCnRixz+OLKFOZYisBAIhoj6CSmrTWud5EiKd77KRqVjJ0DPXpQ==?iv=YNXmoPI7amNVoM3R3LmRRg==","sig":"0bac6b7eaf213db338e6100748af3b996e6145cc3b503229cd4f714848e75e783c83481e66548d1ad96a2c350386fe73885d13b51d32491b319bc65bfb81f2c7"}"###,
            ###"{"kind":4,"id":"ec028bfad005ec3a95295e323fc606f7e938ed25baba31ab4f3f89410841a766","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718518390,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"13JTZ+RrrFArYCqCHEphTA==?iv=TtZXLga6Ou7ECwXAAI1bNQ==","sig":"d518ef993ac749d92afb12e72309763dfeffb92b3850874b5842d2280f5ad8a37e526be172d651d0ed26d9f9124da8233fe5c9f57b717f37c78c2b10b392a827"}"###,
            ###"{"kind":4,"id":"b6b18a1ee2b17fefc8ff732e1d45fdfc0400b57d82c04a24f4db04d3301d2fbf","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718518374,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"FPNq1n3iHcXApn/q04/m4Kg7IlYC2b1ZOTl3kRhdCFo=?iv=AskYQZxQQMeL7N760phicg==","sig":"6bdb0eb4737c391cf21f99630297aa8a261addd53529740bcd3275a47f2733f59fbb87fd3e3bf4c755d26c615b7da837ceb7a26a6c46267a993b2f84b0c9855e"}"###,
            ###"{"kind":4,"id":"1e205b435d0c00228029adf5ebe2ec021475ecd31eb3d19784610d36709231cc","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718398435,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","wss://nostr.wine/"]],"content":"+wzKbJLOTA5tQOIwdHN+itSYO6YOQMiPId8eti9JeVRhUUku9Nq8vLcPOf0aEH7pIMG50Xa68sRSSvvyyziiCnW/JwDUxBjkgNeQs7Y6ltpJnST0SCcemQFPlqO31/q50B463TMr1iaw8ZrEWgoogA==?iv=xpQ7b9hGhpqq1pOTIMYvxA==","sig":"c83f586a061d10ff6b799448ee8328eae103c941607b4f4ff637c2ffe2271f5f41cdc5edcdcc24883f56108506554388721e7ce1894f1d68ec7ed177f7891e15"}"###,
            ###"{"kind":4,"id":"ecda8b3f1ded713891d8184c32720687934b0ad40e153e708b3038d310066d99","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718398355,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","wss://nostr.wine/"]],"content":"aF2+zxXI1DGMZJOB3pfZhJFlvUG7Gg/96PBBng8OYVlBg8h+uzqMMBt0hDhDEGp8?iv=cxOdljDbkefnn1v1SmhiPA==","sig":"85983c4577da73a3096729f832c16b3a5a6308e17c2c4655791639e0e2a06fa072dd3119934221f5bb0af686a67ad7de4ba969c4af6506bf6b52f93b989f2792"}"###,
            ###"{"kind":4,"id":"053c6e15b0c256486fcdb07a2fec4e75597987964b1af04a086e8924c3fffa23","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1718193803,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"c8MUKy8M7xOkG+6pZPI+SpMm6+LCd1iDmRAFJZbX3vl6ThKNwOmU6OnknW2XLLHiJ3oxp1Z+B987WMyneDnNzjOWYMOmJQ3a0fj3VAU8sOE=?iv=9nCGQIs2+IxWbkCJw9JaKA==","sig":"c0eebcb2e281fe9e784c14208e236b1539fc21924ffe2ba85f49da32959bbbc06d4b07ae73b2048653a56ae38346766577a4b136c049b73858a4b6e1f786d341"}"###,
            ###"{"kind":4,"id":"4c82a849fddb62f138ccc11b4181252993fa2b27d4bd996ae52b18214a0072e9","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1717535919,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"oBsLJlTRKSBpDpaW6KwqXHCbO+9pZrdt2IV3o7eqovQ=?iv=UlyA/IvAVet2We9wOgFcIA==","sig":"32492c5f33760c912354c76362155baa7afd13cbab070cc2b01bfa4bf484670d992119c5aec934f4d03d690aead4716b563b6c8c6f977f8fed10bd5117af4233"}"###,
            ###"{"kind":4,"id":"021712078ff8a81be4d058718d911cf7b8840e0066c2e0df9d412173d97bbae6","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1717499726,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"tGphNFSe5M8CThKpdUohTA==?iv=tREIzIL/FvA2Shtom2wVmg==","sig":"531b0e8492ad5185daf69096452a164ee556db88cbbb2955fbe74b176de66dc383e4f8e5cfbb804eed70afc8928ab13c9476c0e3d8d2c630b772f1758641a88c"}"###,
            ###"{"kind":4,"id":"ebe7d678a2dd1adc1d92d145ae28cd17db7a76d83e42e0fd6dce63258ab30810","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1717495004,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","wss://nostr.wine/"]],"content":"FQ1H5k1WRXGNr4+d/LUEvmycG1U9+pV3vU4L9dvis15YW2yJyebumMmOwrLyiQRzscb4Y4IasvsV0RahZSrmUPJRNkogHQfCTy7QO+UjfnXfOwIOIqj4S5/7FcMS1aTflHCiuPWdpqlSNdNGmdozql/ou+duAtSLT8ZP6KJQCEVbUBqeQ7JJtJBg4WncETpVbMnTDZLNnUZzDiL907USl4gRPBvAtu1UzKOIAxafzA0ibNpiVmuX/6mvFZTLOxlc54SRwxDrrIQ278pN+3fQcCRDMo3V2mEE2tYKI/5duAIeaFS0jS1sTevK3AboC5I5em++NxNSuQWxUrwSMFngapbhkTrvy+9RkNeJsomaERmb3uA/FBWgCJc0oJsHAkTIRcUiVRxo7gk6uoMFVQgBCpK5HFLbeWGmqsFD6INUQ9ecWpSXVcuV7uP82IlvzTTH?iv=msBZh+JCRapwtzJbmE0A5w==","sig":"352cd7c8b95c1b1fe6575015267c72ed4062065c6762455fa74e5e0bc4c83978aa2dca8a96a48937e3d1e9fb5fe2290a5dfe64627d824b03ad2177494f78d9f3"}"###,
            ###"{"kind":4,"id":"e715f8f4f57fd8834175170b2402e2a4f83420b81fca2052fc9371b22544884d","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1717476834,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"75bohuj/MpROwvhRxWCFXBml1XnA7uvnxyrRWWkq07+0ANqfWtp34+RCekj5H0Kc07dvyCTlJ2dmWL0Ar/Dr3tzB2u6FzZixWf9XHfCBzNsQnV6aJ1+e5U51MzJk+12JehAoTpHeOWmzmAsMbB17zU4k8bOdAuKePhff7It/qJmhXIHLb3GpsnGHpkka13lJ9145P7wV/OyngbkLpVUnjA==?iv=xzdhwt7dZhgULTX3bswq0Q==","sig":"39f24a4327b2dcf6c341afc29a187f3f43245116bbeb76eeafd081d81134067278fddee774bad3e2c63d0b00f97215c745aa9fc67c5f39c9b330063c84151b05"}"###,
            ###"{"kind":4,"id":"ada83b8afd47412c8b05ddcd3e6a06af045a4aff7481bc21ccebff919ac494a8","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1717428319,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"61YpkO7uJxsb1/fMIQfJb3mzZMDXo7To5WCwlvVdDVPdntfuzzbbh4M0pvtFzFUsd9dmkSjzHZloDrJl4QUu4Juy8seLqr/HaA2Ux7lx9DGgmWk1WjFyBRpQq4ySmMir9YlZFDKOLUFWNDvyZBPy/1w7rWVKOEbC89050D4pTsuk7fOxhkuqaRuxzsczweXj?iv=Tl7RYw0NUf9g4IcTz7vNgg==","sig":"ba05941b63bde19be04849d0574e9266223a381c60089b7c479c4f77a7d6eceb8d81bb8361051b875db7f66a06b86008c6d7ef4ed3ea9fdd91446b31f4c8645c"}"###,
            ###"{"kind":4,"id":"cdbe4a26bc331f23cae8ad8670057775b626f46913b350c1de46b2c090e7e217","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1709722545,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"evPIJGERb8rZb1SBh4W0NQ==?iv=aZg/2HkCAhNQsOno9PXwOA==","sig":"6930ec65c1430ad454300d2e03c4a8de6ef4ec1464d53ec3c8984d31ded7171aee1438962c47b5b95df3718be2c7f83d18a3ad74e204f0e5ab9062a28f00cf91"}"###,
            ###"{"kind":4,"id":"13ddb093428349ddc88597b867038556310da51d491adf5d960fc1552929ca0b","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1709722544,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"HkBYG0AS8U78AauDLBuzkg==?iv=AbYBd9XyiLXvQdaqs0Imfw==","sig":"78f57440531ac2f831586c7faa89fca33a2d3e733c6ef3c001944a4d9b97e0423a879b192cab7c5b82115971628cf680c6494d7b19fadeda2f1ce7181aabebc9"}"###,
            ###"{"kind":4,"id":"9c60427cb9cf6b3854b6a0389660b2e3f87a618a81e051316a11c963f2d9d80b","pubkey":"06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","created_at":1709722525,"tags":[["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]],"content":"qleet56rhH6CIUbtgLHahnoEhlKkP2udfsUbZbfMOfx4ghY+753Jiuqbb5NIAR7voVs5+EO7ZMWePa8lOA+47WWxTpV4AK5pOSu7VeymOC2FgNH5yJ6ZpgaChLDszZfDG3dFfPjUyq1kQZNlLH0esTpFDsE557DPikzKXa0+OaBG/N23wuMS1RLsgUqClygiuLWrgCDUZ83Fd7UlKIZtpFd88Lcm2EWIbrZf62HhjKs=?iv=01NdXa2Gc0reSWq66GW/3w==","sig":"cc051fb04694f779baaa76e13c64f327aed4ad8c31a32bb962d7ac15e532225d964a652acc616a392fe374a8edcbc5d279698edd8631b338c4caf5bcf1ecdeba"}"###,

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
