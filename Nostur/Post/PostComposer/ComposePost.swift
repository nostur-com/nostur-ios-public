//
//  ComposePost.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/10/2023.
//

import SwiftUI
import NavigationBackport
import UniformTypeIdentifiers

// TODO: Should add drafts and auto-save
// TODO: Need to create better solution for typing @mentions

struct ComposePost: View {
    public var replyTo: ReplyTo? = nil
    public var quotePost: QuotePost? = nil
    public var directMention: NRContact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind = .textNote
    public var highlight: NewHighlight?
    
    @State private var isAuthorSelectionShown = false
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    @StateObject private var vm = NewPostModel()
    
    @State private var gifSheetShown = false
    @State private var photoPickerShown = false
    @State private var videoPickerShown = false
    @State private var cameraSheetShown = false
    
    @State private var selectedVideoURL: URL?
    
    @Namespace private var textfield
    @State private var replyToNRPost: NRPost?
    @State private var quotingNRPost: NRPost?
    @State private var isTargeted: Bool = false
    
    @ObservedObject var settings: SettingsStore = .shared
    
    @State private var showAudioRecorder: Bool = false
    @State private var showSwitchBackButton: Bool = true
    
    private var showAutoPilotPreview: Bool {
        guard !SettingsStore.shared.lowDataMode, SettingsStore.shared.enableOutboxPreview else { return false } // Don't continue with additional outbox relays on low data mode, or settings toggle
        guard SettingsStore.shared.enableOutboxRelays, vpnGuardOK() else { return false } // Check if Enhanced Relay Routing toggle is turned on
        guard ConnectionPool.shared.preferredRelays != nil else { return false }
        
        return true
    }
    
    @State private var didLoad = false
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        Container { // Needed because else we are stuck in ProgressView() forever
            if let account = vm.activeAccount {
                if showAudioRecorder {
                    VStack {
                        
                        if let replyToNRPost = replyToNRPost {
                            // Reply, so full-width false and connecting line to bottom
                            KindResolver(nrPost: replyToNRPost, fullWidth: false, hideFooter: true, missingReplyTo: true, isReply: false, isDetail: false, isEmbedded: false, connect: .bottom)
                                .environment(\.nxViewingContext, [.preview, .selectableText, .postParent])
                                .onTapGesture { }
                        }
                        
                    
                        
                     
                        
                        HStack(alignment: .top) {
                            InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                vm.activeAccount = account
                            }).equatable()
                            
                            VStack(alignment: .leading, spacing: 3) {
                                if replyTo != nil {
                                    ReplyingToEditable(requiredP: vm.requiredP, available: vm.availableContacts, selected: $vm.typingTextModel.selectedMentions, unselected: $vm.typingTextModel.unselectedMentions)
                                        .offset(x: 5.0, y: 4.0)
                                }
                                
                                Text("Tap mic to record a voice message")
                                    .font(.footnote)
                                    .foregroundStyle(theme.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: 5.0, y: 4.0)
                            }
                        }
                        .padding(.top, 10)
                        
                        Spacer()
                        
                        AudioRecorderContentView(vm: vm, replyTo: replyTo, onDismiss: { onDismiss() }, onSwitchBack: {
                            showAudioRecorder = false
                            vm.nEvent?.kind = .comment
                        } )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel", systemImage: "xmark") { onDismiss() }
                                }
                            }
                    }
                    .padding(10)
                    .overlay(alignment: .bottom) {
                        MediaUploadProgress(uploader: vm.uploader) // @TODO: Make progress independent of Uploader type (NIP96 / Blossom)
                            .frame(height: 250)
                            .background(theme.listBackground)
                    }
                    .onAppear {
                        if vm.nEvent?.kind == .comment { // Don't init voice if we toggled voice reply to comment reply
                            return
                        }
                        
                        // Only ROOT voice message here. (reply voice message is created when .loadReplyTo() is called)
                        if replyTo == nil {
                            var voiceMessageEvent = NEvent(content: "")
                            voiceMessageEvent.kind = .shortVoiceMessage
                            vm.nEvent = voiceMessageEvent
                        }
                        else { // Voice comment to other kind??? hmm lets try
                            vm.nEvent?.kind = .shortVoiceMessageComment
                        }
                    }
                }
                else {
                    GeometryReader { geo in
                        ScrollViewReader { proxy in
                            ScrollView {
                                switch kind {
                                case .highlight:
                                    VStack {
                                        HStack(alignment: .top) {
                                            InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                                vm.activeAccount = account
                                            }).equatable()
                                            
                                            textEntry
                                                .frame(height: max(50, ((geo.size.height - 90) * 0.5 )))
                                                .id(textfield)
                                        }
                                        .padding(.top, 10)
                                        
                                        if let highlight {
                                            VStack {
                                                Text(highlight.selectedText)
                                                    .italic()
                                                    .padding(20)
                                                    .overlay(alignment:.topLeading) {
                                                        Image(systemName: "quote.opening")
                                                            .foregroundColor(Color.secondary)
                                                    }
                                                    .overlay(alignment:.bottomTrailing) {
                                                        Image(systemName: "quote.closing")
                                                            .foregroundColor(Color.secondary)
                                                    }
                                                
                                                if let selectedAuthor = vm.selectedAuthor {
                                                    HStack {
                                                        Spacer()
                                                        PFP(pubkey: selectedAuthor.pubkey, contact: selectedAuthor, size: 20)
                                                        Text(selectedAuthor.authorName)
                                                    }
                                                    .padding(.trailing, 40)
                                                }
                                                HStack {
                                                    Spacer()
                                                    if let md = try? AttributedString(markdown:"[\(highlight.url)](\(highlight.url))") {
                                                        Text(md)
                                                            .lineLimit(1)
                                                            .font(.caption)
                                                    }
                                                }
                                                .padding(.trailing, 40)
                                            }
                                            .padding(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 15)
                                                    .stroke(.regularMaterial, lineWidth: 1)
                                            )
                                            .navigationTitle(String(localized:"Share highlight", comment:"Navigation title for screen to Share a Highlighted Text"))
                                            .sheet(isPresented: $isAuthorSelectionShown) {
                                                NBNavigationStack {
                                                    ContactsSearch(followingPubkeys: follows(),
                                                                   prompt: "Search", onSelectContact: { selectedContact in
                                                        vm.selectedAuthor = selectedContact
                                                        isAuthorSelectionShown = false
                                                    })
                                                    .equatable()
                                                    .environment(\.theme, theme)
                                                    .environmentObject(la)
                                                    .navigationTitle(String(localized:"Find author", comment:"Navigation title of Find author screen"))
                                                    .navigationBarTitleDisplayMode(.inline)
                                                    .toolbar {
                                                        ToolbarItem(placement: .cancellationAction) {
                                                            Button("Cancel", systemImage: "xmark") {
                                                                isAuthorSelectionShown = false
                                                            }
                                                        }
                                                    }
                                                }
                                                .nbUseNavigationStack(.never)
                                                .presentationBackgroundCompat(theme.listBackground)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            withAnimation {
                                                proxy.scrollTo(textfield)
                                            }
                                        }
                                    }
                                case .picture:
                                    VStack(alignment: .leading) {
                                        HStack(alignment: .top) {
                                            InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                                vm.activeAccount = account
                                            }).equatable()
                                            
                                            VStack(alignment: .leading, spacing: 0) {
                                                PostHeaderView(pubkey: account.publicKey, name: account.anyName, via: "Nostur", createdAt: Date.now, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: false)
                                            }
                                        }
                                        .padding(.top, 10)
                                        .zIndex(200)
                                        
                                        textEntry
                                            .id(textfield)
                                            .onReceive(receiveNotification(.newPostFirstImageAppeared), perform: { _ in
                                                guard kind == .picture else { return }
                                                withAnimation {
                                                    proxy.scrollTo(textfield, anchor: .bottom)
                                                }
                                            })
                                        
                                        if let singleRelay = Drafts.shared.lockToThisRelay {
                                            Toggle(isOn: $vm.lockToSingleRelay) {
                                                Text("Lock post to \(singleRelay.url)")
                                            }
                                            .padding(10)
                                        }
                                    }
                                    .padding(10)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            withAnimation {
                                                proxy.scrollTo(textfield, anchor: .bottom)
                                            }
                                        }
                                    }
                                    
                                default: // (.textNote)
                                    VStack {
                                        if let replyToNRPost = replyToNRPost {
                                            // Reply, so full-width false and connecting line to bottom
                                            KindResolver(nrPost: replyToNRPost, fullWidth: false, hideFooter: true, missingReplyTo: true, isReply: false, isDetail: false, isEmbedded: false, connect: .bottom)
                                                .environment(\.availableWidth, geo.size.width - (SettingsStore.shared.fullWidthImages ? 20 : DIMENSIONS.ROW_PFP_SPACE+20))
                                                .environment(\.nxViewingContext, [.preview, .selectableText, .postParent])
                                                .onTapGesture { }
                                        }
                                        
                                        
                                        HStack(alignment: .top) {
                                            InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                                vm.activeAccount = account
                                            }).equatable()
                                            
                                            textEntry
                                                .frame(height: replyTo == nil && quotePost == nil ? max(50, (geo.size.height - 90)) : max(50, ((geo.size.height - 90) * 0.5 )) )
                                                .id(textfield)
                                        }
                                        .padding(.top, 10)
                                        
                                        
                                        if let quotingNRPost = quotePost?.nrPost {
                                            KindResolver(nrPost: quotingNRPost, fullWidth: SettingsStore.shared.fullWidthImages, hideFooter: true, isEmbedded: true)
                                                .environment(\.nxViewingContext, [.preview, .selectableText, .postEmbedded])
                                                .fixedSize(horizontal: false, vertical: true)
                                                .onTapGesture { }
                                                .environment(\.availableWidth, geo.size.width - (SettingsStore.shared.fullWidthImages ? 20 : DIMENSIONS.ROW_PFP_SPACE+20))
                                                .padding(.leading, SettingsStore.shared.fullWidthImages ? 0 : DIMENSIONS.ROW_PFP_SPACE)
                                        }
                                        
                                        if let singleRelay = Drafts.shared.lockToThisRelay {
                                            Toggle(isOn: $vm.lockToSingleRelay) {
                                                Text("Lock post to \(singleRelay.url)")
                                            }
                                            .padding(10)
                                        }
                                    }
                                    .padding(10)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            withAnimation {
                                                proxy.scrollTo(textfield)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .offset(y: vm.showMentioning && (replyTo != nil) ? -150 : 0)
                        .overlay(alignment: .bottom) {
                            MediaUploadProgress(uploader: vm.uploader) // @TODO: Make progress independent of Uploader type (NIP96 / Blossom)
                                .frame(height: geo.size.height * 0.60)
                                .background(theme.listBackground)
                        }
                        .overlay(alignment: .bottom) {
                            MentionChoices(vm: vm)
                                .frame(height: geo.size.height * 0.60)
                                .background(theme.listBackground)
                        }
                        .nbNavigationDestination(item: $vm.previewNRPost, destination: { nrPost in
                            VStack(alignment: .leading) {
                                PostPreview(nrPost: nrPost, kind: kind, replyTo: replyTo, quotePost: quotePost, vm: vm, onDismiss: { onDismiss() })
                                    .environment(\.theme, theme)
                                    .environment(\.availableWidth, geo.size.width)
                                    .environmentObject(la)
                                    .onDisappear {
                                        vm.previewNRPost = nil
                                    }
                                
                                if let nEvent = vm.previewNEvent, showAutoPilotPreview {
                                    AutoPilotSendPreview(nEvent: nEvent)
                                }
                            }                            
                        })
                        .sheet(isPresented: $videoPickerShown) {
                            VideoPickerView(selectedVideoURL: $selectedVideoURL)
                        }
                        .onChange(of: selectedVideoURL, perform: { newValue in
                            guard kind != .picture else { return }
                            if let video = newValue {
                                vm.typingTextModel.pastedVideos.append(PostedVideoMeta(index: vm.typingTextModel.pastedVideos.count, videoURL: video))
                                selectedVideoURL = nil
                            }
                        })
                    }
                    .overlay {
                        ZStack {
                            AnyStatus(filter: "NewPost")
                            
                            if isTargeted {
                                ZStack {
                                    Color.black.opacity(0.7)
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 60))
                                        Text("Drop image...")
                                    }
                                    .font(.largeTitle)
                                    .fontWeightBold()
                                    .foregroundColor(.white)
                                    .frame(maxWidth: 250)
                                    .multilineTextAlignment(.center)
                                }
                                .animation(.default, value: isTargeted)
                            }
                            
                            if #available(iOS 16, *) {
                                PhotosPicker16(vm: vm, kind: kind, photoPickerShown: $photoPickerShown)
                            }
                        }
                    }
                    .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                            if error == nil, let data {
                                // Check if the data is a GIF
                                let isGif = data.starts(with: [0x47, 0x49, 0x46]) // GIF magic number
                                DispatchQueue.main.async {
                                    let imageType: PostedImageMeta.ImageType = isGif ? .gif : .jpeg
                                    if kind == .picture { // Only 1 main picture for kind:20
                                        self.vm.typingTextModel.pastedImages = [
                                            PostedImageMeta(
                                                index: 0,
                                                data: data,
                                                type: imageType,
                                                uniqueId: UUID().uuidString
                                            )
                                        ]
                                    }
                                    else { // multiple images possible for others
                                        self.vm.typingTextModel.pastedImages.append(
                                            PostedImageMeta(
                                                index: self.vm.typingTextModel.pastedImages.count,
                                                data: data,
                                                type: imageType,
                                                uniqueId: UUID().uuidString
                                            )
                                        )
                                    }
                                }
                            }
                        }
                        return true
                    }
                    // TODO: Add drag n drop for video
                }
                
            }
            else {
                ProgressView()
            }
        }
        .onAppear {
            Importer.shared.delayProcessing()
            guard !didLoad else { return }
            didLoad = true
            vm.activeAccount = account()
            
            if #available(iOS 16.0, *), kind == .picture {
                var pictureEvent = NEvent(content: "")
                pictureEvent.kind = .picture
                vm.nEvent = pictureEvent
            }
            else if kind == .highlight, let highlight {
                var highlightEvent = NEvent(content: highlight.selectedText)
                highlightEvent.kind = .highlight
                highlightEvent.tags.append(NostrTag(["r", highlight.url]))
                vm.nEvent = highlightEvent
            }
            else if let replyTo {
                vm.loadReplyTo(replyTo)
                self.replyToNRPost = replyTo.nrPost
                if replyTo.nrPost.kind == 1222 || replyTo.nrPost.kind == 1244 {
                    showAudioRecorder = true
                }
            }
            else if let quotePost {
                vm.loadQuotingEvent()
                self.quotingNRPost = quotePost.nrPost
            }
            else {
                vm.nEvent = NEvent(content: "")
            }
            ConnectionPool.shared.connectAllWrite()
        }
        .background(theme.listBackground)
    }
    
    @ViewBuilder
    var textEntry: some View {
        Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind, kind: kind, selectedAuthor: $vm.selectedAuthor, showAudioRecorder: $showAudioRecorder)
    }
}

#Preview("New Post") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
        pe.loadContacts()
    }) {
        VStack {
            Button("New Post") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        ComposePost(onDismiss: { })
                    }
                    .nbUseNavigationStack(.never)
                }
        }
    }
}

#Preview("New Picture Post") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
        pe.loadContacts()
    }) {
        VStack {
            Button("New Post") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        ComposePost(onDismiss: { }, kind: .picture)
                    }
                    .nbUseNavigationStack(.never)
                }
        }
    }
}

#Preview("New Short Voice Message") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
        pe.loadContacts()
    }) {
        VStack {
            Button("New Post") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        ComposePost(onDismiss: { }, kind: .shortVoiceMessage)
                    }
                    .nbUseNavigationStack(.never)
                }
        }
    }
}

#Preview("New Highlight") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
        pe.loadContacts()
    }) {
        VStack {
            Button("New Highlight") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        
                        let example = NewHighlight(url: "https://nostur.com", selectedText: "This is amazing, this is some text that is being highlighted by Nostur highlightur", title:"Nostur - a nostr client for iOS/macOS")

                        ComposePost(onDismiss: { }, kind: .highlight, highlight: example)
                    }
                    .nbUseNavigationStack(.never)
                }
        }
    }
}

#Preview("New Reply") {
    PreviewContainer({ pe in
        pe.loadAccounts()
        pe.loadPosts()
        pe.loadContacts()
    }) {
        VStack {
            Button("New Post") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        if let nrReplyTo = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                            ComposePost(replyTo: ReplyTo(nrPost: nrReplyTo), onDismiss: { })
                        }
                    }
                }
        }
    }
}

#Preview("New Voice Reply") {
    PreviewContainer({ pe in
        pe.parseEventJSON([###"{"content":"https://npub1cgcwm56v5hyrrzl5ty4vq4kdud63n5u4czgycdl2r3jshzk55ufqe52ndy.blossom.band/a8218854acc7785f8d5d2000bf95a480ec7ef81ed34ff1dc47c4630d457b83a6.mp4","sig":"40b81ce263c429c06d88de6c3a33fa548578eb52c882051c9b254560c7397c1947a7c2e125d782864dbe2eed07e81f378ac84e24c73be11ee9e11baf5f860b43","tags":[["imeta","url https://npub1cgcwm56v5hyrrzl5ty4vq4kdud63n5u4czgycdl2r3jshzk55ufqe52ndy.blossom.band/a8218854acc7785f8d5d2000bf95a480ec7ef81ed34ff1dc47c4630d457b83a6.mp4","duration 51","waveform 0.004201829437995552 0.1142103350430057 0.43174654727233186 0.5229314294197938 0.22569140008715555 0.09033115518699292 0.01114486257703379 0.19737698956074196 0.37434808042017376 0.27857154055066596 0.2218687310839273 0.2955642206981163 0.25441732695684854 0.000032908529798580295 0.18291360154973546 0.0013525079821871233 0 0 0 0.0039864314885253 0.2941087787653154 0.4064170888166966 0.34966808423353063 0.33292546613934215 0.2835916501853135 0.28782210814401454 0.2366818006710173 0.16079851586851754 0.032515611962715844 0.004588162264495497 0 0.38998164514033273 0.2382420438480493 0.22954782313546251 0.28334960071989357 0.24979438011774774 0.17414680177442102 0.37924803832637916 0.07394749645688055 0.0001329989366899501 0.28938743804200506 0.5395710889950673 0.3804477135290114 0.22625714375036632 0.35535009767379877 0.22741313549757497 0.23497218415788504 0.2762070197639018 0.19636850273456075 0.20290360747672803 0.05496752364349224 0.48481011225347803 0.33057541168174065 0.13496673872917467 0.5527362047645379 0.29108917468254847 0.16955781280193924 0.19810807450578308 0.24205374942718033 0.1582141257896855 0.4902229339651341 0.2310274273904644 0.3001810061785608 0.003698714219486976 0.5653072929945436 0.4192506063698652 0.21833678610413854 0.3855482052759224 0.29801634869746885 0.19863830178977776 0.21971105836831 0.22677287527101533 0.21357531122109952 0.1818311185112476 0.013571013494789038 0.1690159390881684 0.04426054269752572 0 0.20823331012177831 0.3851604826893852 0.2633158295196734 0.5202343058038011 0.36049045305817873 0.4019926456689473 0.3638399417895293 0.05879440985299944 0.09939506282636562 0.0020920428019922696 0.4635555085582592 0.40576531822620265 0.44135523423865053 0.00025527147073964887 0.24865015989276124 0.2621184951267706 0.3940824018014514 0.20158430161177668 0.06890933334487073 0.25973563542509115 0.36016571451355484 0.004624447456050344"]],"pubkey":"c230edd34ca5c8318bf4592ac056cde37519d395c0904c37ea1c650b8ad4a712","kind":1222,"id":"44983b6fe368b39e5c1fe90b2e53b34273ee41968c1bf13d17dd7e60324ac4ad","created_at":1758414549}"###])
    }) {
        VStack {
            Button("New Voice Reply") { }
                .sheet(isPresented: .constant(true)) {
                    NBNavigationStack {
                        if let nrReplyTo = PreviewFetcher.fetchNRPost("44983b6fe368b39e5c1fe90b2e53b34273ee41968c1bf13d17dd7e60324ac4ad") {
                            ComposePost(replyTo: ReplyTo(nrPost: nrReplyTo), onDismiss: { })
                        }
                    }
                }
        }
    }
}


@available(iOS 16.0, *)
struct PhotosPicker16: View {
    @ObservedObject public var vm: NewPostModel
    public var kind: NEventKind
    @Binding public var photoPickerShown: Bool
    @StateObject private var ipm = MultipleImagePickerModel()
    
    var body: some View {
        Color.clear
            .photosPicker(isPresented: $photoPickerShown, selection: $ipm.imageSelection,
                      maxSelectionCount: 12,
                      matching: .images, photoLibrary: .shared())
        
            .onChange(of: ipm.newImages) { newImages in
                for (index, newImage) in newImages.enumerated() {
                    guard let data = newImage.pngData() else { return }
                    let imageType: PostedImageMeta.ImageType = newImage.gifData() != nil ? .gif : .jpeg
                    vm.typingTextModel.pastedImages.append(
                        PostedImageMeta(
                            index: vm.typingTextModel.pastedImages.count + index,
                            data: data,
                            type: imageType,
                            uniqueId: UUID().uuidString
                        )
                    )
                }
                ipm.newImages = []
            }
    }
}
