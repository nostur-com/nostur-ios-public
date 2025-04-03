//
//  Entry.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/10/2023.
//

import SwiftUI
import NavigationBackport

struct Entry: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes: Themes
    private var vm: NewPostModel
    @ObservedObject var typingTextModel: TypingTextModel
    @Binding var photoPickerShown: Bool
    @Binding var videoPickerShown: Bool
    @Binding var gifSheetShown: Bool
    @Binding var cameraSheetShown: Bool
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
            default:
            String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
        }
    }
    
    private var shouldDisablePostButton: Bool {
        (kind == .picture && typingTextModel.pastedImages.isEmpty) || typingTextModel.sending || typingTextModel.uploading || (typingTextModel.text.isEmpty && typingTextModel.pastedImages.isEmpty && typingTextModel.pastedVideos.isEmpty)
    }
    
    init(vm: NewPostModel, photoPickerShown: Binding<Bool>, videoPickerShown: Binding<Bool>, gifSheetShown: Binding<Bool>, cameraSheetShown: Binding<Bool>, replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, directMention: NRContact? = nil, onDismiss: @escaping () -> Void, replyToKind: Int64?, kind: NEventKind? = nil) {
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
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        VStack(alignment: .leading, spacing: 3) {

            if kind == .picture {
                ImagePreviews(pastedImages: $typingTextModel.pastedImages, showButtons: false)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, -10)
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
                pastedImages: $typingTextModel.pastedImages,
                pastedVideos: $typingTextModel.pastedVideos,
                shouldBecomeFirstResponder: true,
                highlightRules: NewPostModel.rules,
                photoPickerTapped: {
                    photoPickerShown = true
                },              
                videoPickerTapped: {
                    videoPickerShown = true
                },
                gifsTapped: {
                    gifSheetShown = true
                },
                cameraTapped: {
                    cameraSheetShown = true
                },
                nestsTapped: {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        sendNotification(.showCreateNestsSheet)
                    }
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
                    .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
            }
            .sheet(isPresented: $cameraSheetShown) {
                NBNavigationStack {
                    CameraView(onUse: { uiImage in
                        typingTextModel.pastedImages.append(PostedImageMeta(index: typingTextModel.pastedImages.count, imageData: uiImage, type: .jpeg, uniqueId: UUID().uuidString))
                    })
                    .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
            }
            
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
                        if kind != .picture {
                            Button {
                                if IS_CATALYST { // MacOS can reuse same weird sheet
                                    sendNotification(.showCreateNestsSheet)
                                }
                                else { // IPAD needs to dismiss first
                                    onDismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                                        sendNotification(.showCreateNestsSheet)
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
                            
                            if kind != .picture {
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
                    
                    if kind != .picture {
                        Button(String(localized: "Preview", comment:"Preview button when creating a new post")) {
                            vm.showPreview(quotePost: quotePost, replyTo: replyTo)
                        }
                        .disabled(typingTextModel.uploading)
                    }
                    
                    Button {
                        typingTextModel.sending = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.vm.sendNow(replyTo: replyTo, quotePost: quotePost, onDismiss: { onDismiss() })
                        }
                    } label: {
                        if (typingTextModel.uploading || typingTextModel.sending) {
                            ProgressView().colorInvert()
                        }
                        else {
                            Text("Post.verb", comment: "Button to post (publish) a post")
                        }
                    }
                    .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
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
    }
}
