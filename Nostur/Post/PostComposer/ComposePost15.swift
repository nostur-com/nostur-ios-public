//
//  ComposePost15.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2024.
//

import SwiftUI
import NavigationBackport
import UniformTypeIdentifiers

// TODO: We don't have a image picker yet for iOS 15
struct ComposePost15: View {
    public var replyTo: ReplyTo? = nil
    public var quotePost: QuotePost? = nil
    public var directMention: NRContact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes: Themes
    
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
//    @State private var textHeight:CGFloat = 0
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var waitingForReply: Bool {
        guard replyTo != nil else { return false }
        return replyToNRPost == nil
    }
    
    private var waitingForQuote: Bool {
        guard quotePost != nil else { return false }
        return quotingNRPost == nil
    }
    
    private var showAutoPilotPreview: Bool {
        guard !SettingsStore.shared.lowDataMode, SettingsStore.shared.enableOutboxPreview else { return false } // Don't continue with additional outbox relays on low data mode, or settings toggle
        guard SettingsStore.shared.enableOutboxRelays, vpnGuardOK() else { return false } // Check if Enhanced Relay Routing toggle is turned on
        guard ConnectionPool.shared.preferredRelays != nil else { return false }
        
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
                            VStack {
                                if let replyToNRPost = replyToNRPost {
                                    PostRowDeletable(nrPost: replyToNRPost, hideFooter: true, connect: .bottom, theme: themes.theme)
                                        .onTapGesture { }
                                        .disabled(true)
                                        .padding(.bottom, 10)
                                }
                                
                                HStack(alignment: .top) {
                                    InlineAccountSwitcher(activeAccount: account, onChange: { account in
                                        vm.activeAccount = account
                                    }).equatable()
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, videoPickerShown: $videoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind)
                                        .frame(height: replyTo == nil && quotePost == nil ? max(50, (geo.size.height - 20)) : max(50, ((geo.size.height - 20) * 0.5 )) )
                                        .id(textfield)
                                }
                                
                                if let quotingNRPost = quotingNRPost {
                                    QuotedNoteFragmentView(nrPost: quotingNRPost, theme: themes.theme)
                                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: geo.size.width - 70, isScreenshot: false))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(themes.theme.lineColor.opacity(0.5), lineWidth: 1)
                                        )
                                        .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                                }
                                
                                Spacer()
                            }

                            .padding(.horizontal, 10)
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
                        NBNavigationStack {
                            VStack(alignment: .leading) {
                                PostPreview(nrPost: nrPost, replyTo: replyTo, quotePost: quotePost, vm: vm, onDismiss: { onDismiss() })
                                    .environmentObject(themes)
                                
                                if let nEvent = vm.previewNEvent, showAutoPilotPreview {
                                    AutoPilotSendPreview(nEvent: nEvent)
                                }
                            }
                        }
                        .nbUseNavigationStack(.never)
                        .presentationBackgroundCompat(themes.theme.listBackground)
                    }
                    .sheet(isPresented: $videoPickerShown) {
                        VideoPickerView(selectedVideoURL: $selectedVideoURL)
                    }
                    .onChange(of: selectedVideoURL, perform: { newValue in
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
                    return true
                }
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
