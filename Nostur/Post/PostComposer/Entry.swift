//
//  Entry.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/10/2023.
//

import SwiftUI

struct Entry: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme:Theme
    private var vm:NewPostModel
    @ObservedObject var typingTextModel:TypingTextModel
    @Binding var photoPickerShown:Bool
    @Binding var gifSheetShown:Bool
    private var replyTo:Event?
    private var quotingEvent:Event?
    private var directMention:Contact?
    static let PLACEHOLDER = String(localized:"What's happening?", comment: "Placeholder text for typing a new post")
//    @Namespace private var images
    
    init(vm:NewPostModel, photoPickerShown:Binding<Bool>, gifSheetShown:Binding<Bool>, replyTo: Event? = nil, quotingEvent: Event? = nil, directMention:Contact? = nil) {
        self.replyTo = replyTo
        self.quotingEvent = quotingEvent
        self.directMention = directMention
        self.vm = vm
        self.typingTextModel = vm.typingTextModel
        _photoPickerShown = photoPickerShown
        _gifSheetShown = gifSheetShown
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(alignment: .leading, spacing: 3) {
            if replyTo != nil {
                HStack(alignment: .top) { // name + reply + context menu
                    ReplyingToEditable(requiredP: vm.requiredP, available: vm.availableContacts, selected: $typingTextModel.selectedMentions)
                        .offset(x: 5.0, y: 4.0)
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
            .background(alignment:.topLeading) {
                Text(Self.PLACEHOLDER).foregroundColor(.gray)
                    .opacity(typingTextModel.text == "" ? 1 : 1)
                    .offset(x: 5.0, y: 4.0)
            }
            .sheet(isPresented: $gifSheetShown) {
                NavigationStack {
                    GifSearcher { gifUrl in
                        typingTextModel.text += gifUrl + "\n"
                    }
                }
                .presentationBackground(theme.background)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.sending = true
                    vm.sendNow(replyTo: replyTo, quotingEvent: quotingEvent, dismiss: dismiss)
                } label: {
                    if (vm.uploading || vm.sending) {
                        ProgressView()
                    }
                    else {
                        Text("Post.verb", comment: "Button to post (publish) a post")
                    }
                }
                .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                .cornerRadius(20)
                .disabled(vm.sending || vm.uploading || typingTextModel.text.isEmpty)
                
            }
        }
    }
}
