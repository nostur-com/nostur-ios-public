//
//  Entry.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/10/2023.
//

import SwiftUI
import NavigationBackport
import NostrEssentials

struct Entry: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme
    private var vm: NewPostModel
    @ObservedObject var typingTextModel: TypingTextModel
    @Binding var photoPickerShown: Bool
    @Binding var videoPickerShown: Bool
    @Binding var gifSheetShown: Bool
    @Binding var cameraSheetShown: Bool
    @Binding var selectedAuthor: Contact?
    @Binding var showAudioRecorder: Bool
    
    private var replyTo: ReplyTo?
    private var quotePost: QuotePost?
    private var directMention: NRContact?
    private var onDismiss: () -> Void
    private var replyToKind: Int64?
    private var kind: NEventKind?
    private var PLACEHOLDER: String {
        switch kind {
            case .picture:
            String(localized:"Add a caption", comment: "Placeholder text for adding a caption")
            case .highlight:
            String(localized:"Add comment", comment: "Placeholder text for adding a comment")
            default:
            String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
        }
    }
    
    @State private var isAuthorSelectionShown = false
    @State private var showVoiceRecorderButton: Bool = true
    
    private var shouldDisablePostButton: Bool {
        (kind == .picture && typingTextModel.pastedImages.isEmpty) || typingTextModel.sending || typingTextModel.uploading || (typingTextModel.text.isEmpty && typingTextModel.pastedImages.isEmpty && typingTextModel.pastedVideos.isEmpty && kind != .highlight)
    }
    
    init(vm: NewPostModel, photoPickerShown: Binding<Bool>, videoPickerShown: Binding<Bool>, gifSheetShown: Binding<Bool>, cameraSheetShown: Binding<Bool>, replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, directMention: NRContact? = nil, onDismiss: @escaping () -> Void, replyToKind: Int64?, kind: NEventKind? = nil, selectedAuthor: Binding<Contact?>, showAudioRecorder: Binding<Bool>) {
        self.replyTo = replyTo
        self.quotePost = quotePost
        self.directMention = directMention
        self.vm = vm
        self.typingTextModel = vm.typingTextModel
        self.onDismiss = onDismiss
        self.replyToKind = replyToKind
        self.kind = kind
        _photoPickerShown = photoPickerShown
        _videoPickerShown = videoPickerShown
        _gifSheetShown = gifSheetShown
        _cameraSheetShown = cameraSheetShown
        _selectedAuthor = selectedAuthor
        _showAudioRecorder = showAudioRecorder
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        VStack(alignment: .leading, spacing: 3) {

            if kind == .picture {
                if typingTextModel.pastedImages.isEmpty {
                    HStack(alignment: .top) {
                        Spacer()
                        
                        Button {
                            cameraSheetShown = true
                        } label: {
                            Image(systemName: "camera")
                        }
                        .accessibilityHint(Text("Take a photo"))
                        .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))

                        .padding()
                        
                        Button {
                            photoPickerShown = true
                        } label: {
                            Image(systemName: "photo")
                        }
                        .accessibilityHint(Text("Choose a photo"))
                        .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                        .padding()
        
                        Spacer()
                    }
                    .font(.largeTitle)
                }
                else {
                    ImagePreviews(pastedImages: $typingTextModel.pastedImages, showButtons: false)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, -10)
                }
            }
            
            if replyTo != nil {
                HStack(alignment: .top) { // name + reply + context menu
                    if replyToKind == 443 {
                        Text("Commenting on website")
                            .offset(x: 5.0, y: 4.0)
                    }
                    else {
                        ReplyingToEditable(requiredP: vm.requiredP, available: vm.availableContacts, selected: $typingTextModel.selectedMentions, unselected: $typingTextModel.unselectedMentions)
                            .offset(x: 5.0, y: 4.0)
                    }
                }
                .frame(height: 21.0)
            }
            
            HighlightedTextEditor(
                text: $typingTextModel.text,
                kind: kind,
                showVoiceRecorderButton: $showVoiceRecorderButton,
                pastedImages: $typingTextModel.pastedImages,
                pastedVideos: $typingTextModel.pastedVideos,
                shouldBecomeFirstResponder: true,
                highlightRules: NewPostModel.rules,
                photoPickerTapped: {
                    photoPickerShown = true
                    showVoiceRecorderButton = false
                },
                videoPickerTapped: {
                    videoPickerShown = true
                    showVoiceRecorderButton = false
                },
                gifsTapped: {
                    gifSheetShown = true
                    showVoiceRecorderButton = false
                },
                cameraTapped: {
                    cameraSheetShown = true
                    showVoiceRecorderButton = false
                },
                nestsTapped: {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        sendNotification(.showCreateNestsSheet, vm.activeAccount)
                    }
                },
                voiceMessageTapped: {
                    showAudioRecorder = true
                }
            )
            .introspect { editor in
                // Needed so we can update cursors position on @mention autocomplete
                if (vm.textView == nil) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        vm.textView = editor.textView
                        if let directMention = directMention {
                            vm.directMention(directMention)
                        }
                    }
                }
            }
            .background(alignment: .topLeading) {
                Text(self.PLACEHOLDER).foregroundColor(.gray)
                    .opacity(typingTextModel.text == "" ? 1 : 1)
                    .offset(x: 5.0, y: 8.0)
            }
            .frame(minHeight: 100)
            .sheet(isPresented: $gifSheetShown) {
                NBNavigationStack {
                    GifSearcher { gifUrl in
                        typingTextModel.text += gifUrl + "\n"
                    }
                    .environment(\.theme, theme)
                }
            }
            .sheet(isPresented: $cameraSheetShown) {
                NBNavigationStack {
                    CameraView(onUse: { uiImage in
                        guard let pngData = uiImage.pngData() else { return }
                        typingTextModel.pastedImages.append(PostedImageMeta(index: typingTextModel.pastedImages.count, data: pngData, type: .png, uniqueId: UUID().uuidString))
                    })
                    .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(theme.listBackground)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
            
            if kind != .picture {
                if !typingTextModel.pastedImages.isEmpty {
                    HStack(spacing: 5) {
                        ImagePreviews(pastedImages: $typingTextModel.pastedImages)
                    }
                }
                if !typingTextModel.pastedVideos.isEmpty {
                    HStack(spacing: 5) {
                        VideoPreviews(pastedVideos: $typingTextModel.pastedVideos)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onDismiss() } label: { Text("Cancel") }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if IS_CATALYST || (UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular) {
                        if kind != .picture && kind != .highlight {
                            Button {
                                if IS_CATALYST { // MacOS can reuse same weird sheet
                                    sendNotification(.showCreateNestsSheet, vm.activeAccount)
                                }
                                else { // IPAD needs to dismiss first
                                    onDismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                                        sendNotification(.showCreateNestsSheet, vm.activeAccount)
                                    }
                                }
                            } label: {
                                Image(systemName: "mic")
                            }
                            .buttonStyle(.borderless)
                            .disabled(typingTextModel.uploading)
                        }
                        
                        Button { cameraSheetShown = true } label: {
                            Image(systemName: "camera")
                        }
                        .buttonStyle(.borderless)
                        .disabled(typingTextModel.uploading)
                        
                        if #available(iOS 16, *) {
                            Button { photoPickerShown = true } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.borderless)
                            .disabled(typingTextModel.uploading)
                            
                            if kind != .picture && kind != .highlight {
                                Button { videoPickerShown = true } label: {
                                    Image(systemName: "video")
                                }
                                .buttonStyle(.borderless)
                                .disabled(typingTextModel.uploading)
                            }
                        }
                        
                        if kind != .picture {
                            Button { gifSheetShown = true } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(typingTextModel.uploading)
                        }
                    }
                    
                    if kind != .highlight {
                        Button(String(localized: "Preview", comment:"Preview button when creating a new post")) {
                            vm.showPreview(quotePost: quotePost, replyTo: replyTo)
                        }
                        .disabled(shouldDisablePostButton)
                        .opacity(shouldDisablePostButton ? 0.25 : 1.0)
                    }
                    
                    if kind == .highlight {
                        if selectedAuthor != nil {
                            Button(String(localized:"Remove author", comment: "Button to Remove author from Highlight")) { selectedAuthor = nil }
                        }
                        else {
                            Button(String(localized:"Include author", comment: "Button to include author in Highlight")) { isAuthorSelectionShown = true }
                        }
                    }
                    
                    Button {
                        typingTextModel.sending = true
            
                        // Need to do these here in main thread
                        guard let account = vm.activeAccount, account.isFullAccount else {
                            sendNotification(.anyStatus, ("Problem with account", "NewPost"))
                            return
                        }
                        let isNC = account.isNC
                        let pubkey = account.publicKey
                      
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // crash if we don't delay
                            Task {
                                await self.vm.sendNow(isNC: isNC, pubkey: pubkey, account: account, replyTo: replyTo, quotePost: quotePost, onDismiss: { onDismiss() })
                            }
                        }
                    } label: {
                        if (typingTextModel.uploading || typingTextModel.sending) {
                            ProgressView().colorInvert()
                        }
                        else {
                            Text("Post.verb", comment: "Button to post (publish) a post")
                        }
                    }
                    .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                    .cornerRadius(20)
                    .disabled(shouldDisablePostButton)
                    .opacity(shouldDisablePostButton ? 0.25 : 1.0)
                }
            }
            
            ToolbarItem(placement: .principal) {
                if let uploadError = vm.uploadError {
                    Text(uploadError).foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $isAuthorSelectionShown) {
            NBNavigationStack {
                ContactsSearch(followingPubkeys: follows(),
                               prompt: "Search", onSelectContact: { selectedContact in
                    selectedAuthor = selectedContact
                    isAuthorSelectionShown = false
                })
                .equatable()
                .environment(\.theme, theme)
                .navigationTitle(String(localized:"Find author", comment:"Navigation title of Find author screen"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isAuthorSelectionShown = false
                        }
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
        
        // Hide voice recording button if not supported
        .onAppear {
            if let replyTo, (replyTo.nrPost.kind != 1222 && replyTo.nrPost.kind != 1244) {
                showVoiceRecorderButton = false
            }
            else if quotePost != nil {
                showVoiceRecorderButton = false
            }
            else if typingTextModel.text != "" {
                showVoiceRecorderButton = false
            }
        }
        .onChange(of: typingTextModel.text) { newText in
            guard showVoiceRecorderButton else { return }
            if !newText.isEmpty {
                showVoiceRecorderButton = false
            }
        }
    }
}
