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
    public var replyTo: ReplyTo? = nil
    public var quotePost: QuotePost? = nil
    public var directMention: NRContact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ComposePost(replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: onDismiss, kind: kind)
        }
        else {
            ComposePost15(replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: onDismiss) // No image picker yet on iOS 15 so remove kind:20 detection
        }
    }
}

@available(iOS 16.0, *)
struct ComposePost: View {
    public var replyTo: ReplyTo? = nil
    public var quotePost: QuotePost? = nil
    public var directMention: NRContact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var screenSpace: ScreenSpace
    
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = MultipleImagePickerModel()
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
        ZStack { // Needed because else we are stuck in ProgressView() forever
            if let account = vm.activeAccount {
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
                                    
                                    if vm.typingTextModel.pastedImages.isEmpty {
                                        HStack(alignment: .top) {
                                            Spacer()
                                            
                                            Button {
                                                cameraSheetShown = true
                                            } label: {
                                                Image(systemName: "camera")
                                            }
                                            .accessibilityHint(Text("Take a photo"))
                                            .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))

                                            .padding()
                                            
                                            Button {
                                                photoPickerShown = true
                                            } label: {
                                                Image(systemName: "photo")
                                            }
                                            .accessibilityHint(Text("Choose a photo"))
                                            .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                                            .padding()
                            
                                            Spacer()
                                        }
                                        .font(.largeTitle)
                                    }
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind, kind: .picture)
//                                        .frame(height: max(50, (geo.size.height - 70)))
//                                        .padding(.horizontal, -10)
                                        .id(textfield)
                                        .onReceive(receiveNotification(.newPostFirstImageAppeared), perform: { _ in
                                            guard kind == .picture else { return }
                                            withAnimation {
                                                proxy.scrollTo(textfield, anchor: .bottom)
                                            }
                                        })
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
                                        
                                        Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind)
                                            .frame(height: replyTo == nil && quotePost == nil ? max(50, (geo.size.height - 90)) : max(50, ((geo.size.height - 90) * 0.5 )) )
                                            .id(textfield)
                                    }
                                    .padding(.top, 10)
                                    
                                    if let quotingNRPost = quotePost?.nrPost {
                                        KindResolver(nrPost: quotingNRPost, fullWidth: true, hideFooter: true, isDetail: false, isEmbedded: true, theme: themes.theme)
                                            .environmentObject(DIMENSIONS.embeddedDim(availableWidth: geo.size.width != 0 ? geo.size.width : dim.listWidth, isScreenshot: false))
                                            .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
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
                                    PostPreview(nrPost: nrPost, replyTo: replyTo, quotePost: quotePost, vm: vm, onDismiss: { onDismiss() })
                                        .environmentObject(themes)
                                        .environmentObject(previewDIM)
                                        .environmentObject(screenSpace)
                                    
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
                                    PostPreview(nrPost: nrPost, replyTo: replyTo, quotePost: quotePost, vm: vm, onDismiss: { onDismiss() })
                                        .environmentObject(themes)
                                        .environmentObject(previewDIM)
                                        .environmentObject(screenSpace)
                                    
                                    if let nEvent = vm.previewNEvent, showAutoPilotPreview {
                                        AutoPilotSendPreview(nEvent: nEvent)
                                    }
                                }
                            }
                            .nbUseNavigationStack(.never)
                            .presentationBackgroundCompat(themes.theme.listBackground)
                        }
                    }
                    .photosPicker(isPresented: $photoPickerShown, selection: $ipm.imageSelection,
                                  maxSelectionCount: kind == .picture ? 1 : 8,
                                  matching: .images, photoLibrary: .shared())
                    .onChange(of: ipm.newImages) { newImages in
                        if kind == .picture, let firstImage = newImages.first {
                            vm.typingTextModel.objectWillChange.send()
                            vm.typingTextModel.pastedImages = [PostedImageMeta(index: 0, imageData: firstImage, type: .jpeg, uniqueId: UUID().uuidString)]
                        }
                        else {
                            for (index, newImage) in newImages.enumerated() {
                                vm.typingTextModel.objectWillChange.send()
                                vm.typingTextModel.pastedImages.append(
                                    PostedImageMeta(index: vm.typingTextModel.pastedImages.count + index, imageData: newImage, type: .jpeg, uniqueId: UUID().uuidString)
                                )
                            }
                        }
                        ipm.newImages = []
                    }
                    .onChange(of: photoPickerShown) { isShown in
                        // Dismiss whole sheet if no image was picked (for kind:20)
                        guard kind == .picture else { return }
                        guard !isShown else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            guard ipm.imageSelection.isEmpty else { return }
                            guard ipm.newImages.isEmpty else { return }
                            if vm.typingTextModel.pastedImages.isEmpty && !photoPickerShown {
                                L.og.debug("No image selected, dismiss")
                                onDismiss()
                            }
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
                    .onAppear {
                        previewDIM.listWidth = geo.size.width != 0 ? geo.size.width : dim.listWidth
                        previewDIM.isPreviewContext = true
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
            Importer.shared.delayProcessing()
            vm.activeAccount = account()
            
            if kind == .picture {
                var pictureEvent = NEvent(content: "")
                pictureEvent.kind = .picture
                vm.nEvent = pictureEvent
            }
            else if let replyTo {
                vm.loadReplyTo(replyTo)
                self.replyToNRPost = replyTo.nrPost
            }
            else if let quotePost {
                vm.loadQuotingEvent()
                self.quotingNRPost = quotePost.nrPost
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
                        ComposePostCompat(onDismiss: { })
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
                        if let nrReplyTo = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                            ComposePostCompat(replyTo: ReplyTo(nrPost: nrReplyTo), onDismiss: { })
                        }
                    }
                }
        }
    }
}
