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
    @EnvironmentObject private var dim: DIMENSIONS
    
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
    
    private var showAutoPilotPreview: Bool {
        guard !SettingsStore.shared.lowDataMode, SettingsStore.shared.enableOutboxPreview else { return false } // Don't continue with additional outbox relays on low data mode, or settings toggle
        guard SettingsStore.shared.enableOutboxRelays, vpnGuardOK() else { return false } // Check if Enhanced Relay Routing toggle is turned on
        guard ConnectionPool.shared.preferredRelays != nil else { return false }
        
        return true
    }
    
    // No need to refresh previewDIM, just pass to PostPreview to fix random width bug
    @State private var previewDIM = DIMENSIONS()
    
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
                        
                        AudioRecorderContentView(vm: vm, replyTo: replyTo, onDismiss: { onDismiss() })
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
                                                .environmentObject(
                                                    DIMENSIONS.embeddedDim(availableWidth: geo.size.width - (SettingsStore.shared.fullWidthImages ? 20 : DIMENSIONS.ROW_PFP_SPACE+20))
                                                )
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
                                    .environmentObject(la)
                                    .environmentObject(previewDIM)
                                
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
                        .onAppear {
                            previewDIM.listWidth = geo.size.width != 0 ? geo.size.width : dim.listWidth
                        }
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
