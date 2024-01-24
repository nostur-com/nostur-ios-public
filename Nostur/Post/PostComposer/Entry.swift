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
    @Binding var gifSheetShown: Bool
    @Binding var cameraSheetShown: Bool
    private var replyTo: Event?
    private var quotingEvent: Event?
    private var directMention: Contact?
    private var onDismiss: () -> Void
    private var replyToKind: Int64?
    static let PLACEHOLDER = String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
    
    private var shouldDisablePostButton: Bool {
        typingTextModel.sending || typingTextModel.uploading || (typingTextModel.text.isEmpty && typingTextModel.pastedImages.isEmpty)
    }
    
    init(vm: NewPostModel, photoPickerShown: Binding<Bool>, gifSheetShown: Binding<Bool>, cameraSheetShown: Binding<Bool>, replyTo: Event? = nil, quotingEvent: Event? = nil, directMention: Contact? = nil, onDismiss: @escaping () -> Void, replyToKind: Int64?) {
        self.replyTo = replyTo
        self.quotingEvent = quotingEvent
        self.directMention = directMention
        self.vm = vm
        self.typingTextModel = vm.typingTextModel
        self.onDismiss = onDismiss
        self.replyToKind = replyToKind
        _photoPickerShown = photoPickerShown
        _gifSheetShown = gifSheetShown
        _cameraSheetShown = cameraSheetShown
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        VStack(alignment: .leading, spacing: 3) {
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
                pastedImages: $typingTextModel.pastedImages,
                shouldBecomeFirstResponder: true,
                highlightRules: NewPostModel.rules,
                photoPickerTapped: {
                    photoPickerShown = true
                },
                gifsTapped: {
                    gifSheetShown = true
                },
                cameraTapped: {
                    cameraSheetShown = true
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
                Text(Self.PLACEHOLDER).foregroundColor(.gray)
                    .opacity(typingTextModel.text == "" ? 1 : 1)
                    .offset(x: 5.0, y: 8.0)
            }
            .sheet(isPresented: $gifSheetShown) {
                NBNavigationStack {
                    GifSearcher { gifUrl in
                        typingTextModel.text += gifUrl + "\n"
                    }
                    .environmentObject(themes)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.background)
            }
            .sheet(isPresented: $cameraSheetShown) {
                NBNavigationStack {
                    CameraView(onUse: { uiImage in
                        typingTextModel.pastedImages.append(PostedImageMeta(index: typingTextModel.pastedImages.count, imageData: uiImage, type: .jpeg))
                    })
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.background)
            }
            if !typingTextModel.pastedImages.isEmpty {
                HStack(spacing: 5) {
                    ImagePreviews(pastedImages: $typingTextModel.pastedImages)
                }
                //                .id(images)
            }
        }
        //        .onChange(of: typingTextModel.pastedImages) { newImages in
        ////            if let newImage {
        ////                vm.pastedImages.append(newImage)
        ////                textHeight = 200
        //
        ////            }
        //            withAnimation {
        //                proxy.scrollTo(images, anchor: .bottom)
        //            }
        //        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onDismiss() } label: { Text("Cancel") }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if IS_CATALYST || (UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular) {
                        Button { cameraSheetShown = true } label: {
                            Image(systemName: "camera")
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.typingTextModel.uploading)
                        
                        if #available(iOS 16, *) {
                            Button { photoPickerShown = true } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.typingTextModel.uploading)
                        }
                        
                        Button { gifSheetShown = true } label: {
                            Image("GifButton")
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.typingTextModel.uploading)
                    }
                    
                    Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                        vm.showPreview(quotingEvent: quotingEvent)
                    }
                    .disabled(vm.typingTextModel.uploading)
                    
                    Button {
                        vm.typingTextModel.sending = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.vm.sendNow(replyTo: replyTo, quotingEvent: quotingEvent, onDismiss: { onDismiss() })
                        }
                    } label: {
                        if (vm.typingTextModel.uploading || vm.typingTextModel.sending) {
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
