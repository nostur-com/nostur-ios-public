//
//  ComposePost.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/10/2023.
//

import SwiftUI

// TODO: Should add drafts and auto-save
// TODO: Need to create better solution for typing @mentions

struct ComposePost: View {
    public var replyTo:Event? = nil
    public var quotingEvent:Event? = nil
    public var directMention:Contact? = nil // For initiating a post from profile view
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var theme:Theme
    @Environment(\.dismiss) public var dismiss
    
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = ImagePickerModel()
    @State private var gifSheetShown = false
    @State private var photoPickerShown = false
    
    @Namespace private var textfield
    @State private var replyToNRPost:NRPost?
    @State private var quotingNRPost:NRPost?
//    @State private var textHeight:CGFloat = 0
    
    private var waitingForReply:Bool {
        guard replyTo != nil else { return false }
        return replyToNRPost == nil
    }
    
    private var waitingForQuote:Bool {
        guard quotingEvent != nil else { return false }
        return quotingNRPost == nil
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
                                    PostRowDeletable(nrPost: replyToNRPost, hideFooter: true, connect: .bottom)
                                        .onTapGesture { }
                                        .disabled(true)
                                }
                                
                                HStack(alignment: .top) {
                                    PostAccountSwitcher(activeAccount: account, onChange: { account in
                                        vm.activeAccount = account
                                    }).equatable()
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, gifSheetShown: $gifSheetShown, replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention)
                                        .frame(height: replyTo == nil && quotingEvent == nil ? (geo.size.height - 20) : ((geo.size.height - 20) * 0.5 ) )
                                        .id(textfield)
                                }
                                .padding(.top, 10)
                                
                                if let quotingNRPost = quotingNRPost {
                                    QuotedNoteFragmentView(nrPost: quotingNRPost)
                                        .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                                }
                            }
//                            .padding(.bottom, 100) // Need some extra space for expanding account switcher
                            .photosPicker(isPresented: $photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                            .onChange(of: ipm.newImage) { newImage in
                                if let newImage { vm.typingTextModel.pastedImages.append(newImage) }
                            }
                            .padding(10)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button { dismiss() } label: { Text("Cancel") }
                                }
                                if IS_CATALYST || (UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular) {
                                    ToolbarItem(placement: .navigationBarTrailing) {
                                        Button { photoPickerShown = true } label: {
                                            Image(systemName: "photo")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(vm.uploading)
                
                                    }
                                    ToolbarItem(placement: .navigationBarTrailing) {
                                        Button { gifSheetShown = true } label: {
                                            Image("GifButton")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(vm.uploading)
                                    }
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                                        vm.showPreview(quotingEvent: quotingEvent)
                                    }
                                    .disabled(vm.uploading)
                                }
                                
                                if let uploadError = vm.uploadError {
                                    ToolbarItem(placement: .principal) {
                                        Text(uploadError).foregroundColor(.red)
                                    }
                                }
                            }
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
                        MentionChoices(vm: vm)
                            .frame(height: geo.size.height * 0.60)
                            .background(theme.background)
                    }
                    .sheet(item: $vm.previewNRPost) { nrPost in
                        NavigationStack {
                            PostPreview(
                                nrPost: nrPost,
                                sendNow: {
                                    vm.sending = true
                                    vm.sendNow(replyTo: replyTo, quotingEvent: quotingEvent, dismiss: dismiss)
                                },
                                uploading: $vm.uploading
                            )
                        }
                        .presentationBackground(theme.background)
                    }
                }
                .overlay {
                    AnyStatus(filter: "NewPost")
                }
            }
            else {
                ProgressView()
            }
        }
        .onAppear {
            vm.activeAccount = account()
            if let replyTo {
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
                    NavigationStack {
                        ComposePost()
                    }
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
                    NavigationStack {
                        if let replyTo = PreviewFetcher.fetchEvent("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                            ComposePost(replyTo: replyTo)
                        }
                    }
                }
        }
    }
}
