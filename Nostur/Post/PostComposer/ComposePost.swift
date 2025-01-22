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

struct ComposePostCompat: View {
    public var replyTo: Event? = nil
    public var quotingEvent: Event? = nil
    public var directMention: Contact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ComposePost(replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: onDismiss, kind: kind)
        }
        else {
            ComposePost15(replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: onDismiss) // No image picker yet on iOS 15 so remove kind:20 detection
        }
    }
}

@available(iOS 16.0, *)
struct ComposePost: View {
    public var replyTo: Event? = nil
    public var quotingEvent: Event? = nil
    public var directMention: Contact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes: Themes
    
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = ImagePickerModel()
    @State private var gifSheetShown = false
    @State private var photoPickerShown = false
    @State private var videoPickerShown = false
    @State private var cameraSheetShown = false
    
    @State private var selectedVideoURL: URL?
    
    @Namespace private var textfield
    @State private var replyToNRPost: NRPost?
    @State private var quotingNRPost: NRPost?
    @State private var isTargeted: Bool = false
//    @State private var textHeight:CGFloat = 0
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var waitingForReply: Bool {
        guard replyTo != nil else { return false }
        return replyToNRPost == nil
    }
    
    private var waitingForQuote: Bool {
        guard quotingEvent != nil else { return false }
        return quotingNRPost == nil
    }
    
    private var showAutoPilotPreview: Bool {
        guard !SettingsStore.shared.lowDataMode, SettingsStore.shared.enableOutboxPreview else { return false } // Don't continue with additional outbox relays on low data mode, or settings toggle
        guard SettingsStore.shared.enableOutboxRelays, vpnGuardOK() else { return false } // Check if Enhanced Relay Routing toggle is turned on
        guard let preferredRelays = ConnectionPool.shared.preferredRelays else { return false }
        
        return true
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ZStack { // Needed because else we are stuck in ProgressView() forever
            if let account = vm.activeAccount, !waitingForReply, !waitingForQuote {
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            switch kind {
                            case .picture:
                                VStack(alignment: .leading) {
                                    HStack(alignment: .top) {
                                        InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                            vm.activeAccount = account
                                        }).equatable()
                                        
                                        VStack(alignment: .leading, spacing: 0) {
                                            PostHeaderView(pubkey: account.publicKey, name: account.anyName, couldBeImposter: 0, via: "Nostur", createdAt: Date.now, displayUserAgentEnabled: settings.displayUserAgentEnabled, singleLine: false)
                                        }
                                    }
                                    .padding(.top, 10)
                                    .zIndex(200)
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind, kind: .picture)
//                                        .frame(height: max(50, (geo.size.height - 70)))
//                                        .padding(.horizontal, -10)
                                        .id(textfield)
                                }
                                
                                .padding(10)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation {
                                            proxy.scrollTo(textfield, anchor: .bottom)
                                        }
                                    }
                                }
                            default:
                                VStack {
                                    if let replyToNRPost = replyToNRPost {
                                        PostRowDeletable(nrPost: replyToNRPost, hideFooter: true, connect: .bottom, theme: themes.theme)
                                            .onTapGesture { }
                                            .disabled(true)
                                    }
                                    
                                    HStack(alignment: .top) {
                                        InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                            vm.activeAccount = account
                                        }).equatable()
                                        
                                        Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind)
                                            .frame(height: replyTo == nil && quotingEvent == nil ? max(50, (geo.size.height - 20)) : max(50, ((geo.size.height - 20) * 0.5 )) )
                                            .id(textfield)
                                    }
                                    .padding(.top, 10)
                                    
                                    if let quotingNRPost = quotingNRPost {
                                        QuotedNoteFragmentView(nrPost: quotingNRPost, theme: themes.theme)
                                            .environmentObject(DIMENSIONS.embeddedDim(availableWidth: geo.size.width - 70, isScreenshot: false))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(themes.theme.lineColor.opacity(0.5), lineWidth: 1)
                                            )
                                            .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                                    }
                                }
                                
                                .padding(10)
                                .onAppear {
                                    signpost(NRState.shared, "New Post", .end, "New Post view ready")
                                    
                                    if let startTime = timeTrackers["NewNote"] {
                                        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                                        print(String(format: "NewNote: Time elapsed: %.3f seconds", timeElapsed))
                                    }
                                }
                                .onAppear {
        //                            textHeight = 300
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
                        MediaUploadProgress(uploader: vm.uploader)
                            .frame(height: geo.size.height * 0.60)
                            .background(themes.theme.background)
                    }
                    .overlay(alignment: .bottom) {
                        MentionChoices(vm: vm)
                            .frame(height: geo.size.height * 0.60)
                            .background(themes.theme.background)
                    }
                    .sheet(item: $vm.previewNRPost) { nrPost in
                        if #available(iOS 16, *) {
                            NavigationStack {
                                VStack(alignment: .leading) {
                                    PostPreview(nrPost: nrPost, replyTo: replyTo, quotingEvent: quotingEvent, vm: vm, onDismiss: { onDismiss() })
                                        .environmentObject(themes)
                                    
                                    if let nEvent = vm.previewNEvent, showAutoPilotPreview {
                                        AutoPilotSendPreview(nEvent: nEvent)
                                    }
                                }
                            }
                            .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                        else {
                            NBNavigationStack {
                                VStack(alignment: .leading) {
                                    PostPreview(nrPost: nrPost, replyTo: replyTo, quotingEvent: quotingEvent, vm: vm, onDismiss: { onDismiss() })
                                        .environmentObject(themes)
                                    
                                    if let nEvent = vm.previewNEvent, showAutoPilotPreview {
                                        AutoPilotSendPreview(nEvent: nEvent)
                                    }
                                }
                            }
                            .nbUseNavigationStack(.never)
                            .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                    }
                    .photosPicker(isPresented: $photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                    .onChange(of: ipm.newImage) { newImage in
                        if let newImage {
                            if kind == .picture { // Only 1 main picture for kind:20
                                vm.typingTextModel.objectWillChange.send()
                                vm.typingTextModel.pastedImages = [PostedImageMeta(index: 0, imageData: newImage, type: .jpeg, uniqueId: UUID().uuidString)]
                            }
                            else { // multiple images possible for others
                                vm.typingTextModel.pastedImages.append(
                                    PostedImageMeta(index: vm.typingTextModel.pastedImages.count, imageData: newImage, type: .jpeg, uniqueId: UUID().uuidString)
                                )
                            }
                            ipm.newImage = nil
                        }
                    }
                    
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
                    }
                }
                .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadDataRepresentation(forTypeIdentifier:  UTType.image.identifier) { data, error in
                        if error == nil, let data, let imageData = UIImage(data: data) {
                            DispatchQueue.main.async {
                                if kind == .picture { // Only 1 main picture for kind:20
                                    self.vm.typingTextModel.pastedImages = [
                                        PostedImageMeta(
                                            index: 0,
                                            imageData: imageData,
                                            type: .jpeg,
                                            uniqueId: UUID().uuidString
                                        )
                                    ]
                                }
                                else { // multiple images possible for others
                                    self.vm.typingTextModel.pastedImages.append(
                                        PostedImageMeta(
                                            index: self.vm.typingTextModel.pastedImages.count,
                                            imageData: imageData,
                                            type: .jpeg,
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
            else {
                ProgressView()
            }
        }
        .onAppear {
            vm.activeAccount = account()
            
            if kind == .picture {
                var pictureEvent = NEvent(content: "")
                pictureEvent.kind = .picture
                vm.nEvent = pictureEvent
                photoPickerShown = true
            }
            else if let replyTo {
                vm.loadReplyTo(replyTo)
                bg().perform {
                    let replyToNRPost = NRPost(event: replyTo)
                    DispatchQueue.main.async {
                        self.replyToNRPost = replyToNRPost
                    }
                }
            }
            else if let quotingEvent {
                vm.loadQuotingEvent(quotingEvent)
                bg().perform {
                    if let quotingEventBG = quotingEvent.toBG() {
                        let quotingNRPost = NRPost(event: quotingEventBG)
                        DispatchQueue.main.async {
                            self.quotingNRPost = quotingNRPost
                        }
                    }
                }
            }
            ConnectionPool.shared.connectAllWrite()
        }
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
                        ComposePostCompat(onDismiss: { }, kind: .picture)
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
                        if let replyTo = PreviewFetcher.fetchEvent("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                            ComposePostCompat(replyTo: replyTo, onDismiss: { })
                        }
                    }
                }
        }
    }
}
