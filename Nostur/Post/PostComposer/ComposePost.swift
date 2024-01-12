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
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ComposePost(replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: onDismiss)
        }
        else {
            ComposePost15(replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: onDismiss)
        }
    }
}

@available(iOS 16.0, *)
struct ComposePost: View {
    public var replyTo:Event? = nil
    public var quotingEvent:Event? = nil
    public var directMention:Contact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes:Themes
    
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = ImagePickerModel()
    @State private var gifSheetShown = false
    @State private var photoPickerShown = false
    @State private var cameraSheetShown = false
    
    @Namespace private var textfield
    @State private var replyToNRPost:NRPost?
    @State private var quotingNRPost:NRPost?
    @State private var isTargeted: Bool = false
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
                                    PostRowDeletable(nrPost: replyToNRPost, hideFooter: true, connect: .bottom, theme: themes.theme)
                                        .onTapGesture { }
                                        .disabled(true)
                                }
                                
                                HStack(alignment: .top) {
                                    PostAccountSwitcher(activeAccount: account, onChange: { account in
                                        vm.activeAccount = account
                                    }).equatable()
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, onDismiss: { onDismiss() }, replyToKind: replyToNRPost?.kind)
                                        .frame(height: replyTo == nil && quotingEvent == nil ? max(50, (geo.size.height - 20)) : max(50, ((geo.size.height - 20) * 0.5 )) )
                                        .id(textfield)
                                }
                                .padding(.top, 10)
                                
                                if let quotingNRPost = quotingNRPost {
                                    QuotedNoteFragmentView(nrPost: quotingNRPost, theme: themes.theme)
                                        .padding(.leading, DIMENSIONS.ROW_PFP_SPACE - 5)
                                }
                            }
//                            .padding(.bottom, 100) // Need some extra space for expanding account switcher
                            .photosPicker(isPresented: $photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                            .onChange(of: ipm.newImage) { newImage in
                                if let newImage { vm.typingTextModel.pastedImages.append(PostedImageMeta(index: vm.typingTextModel.pastedImages.count, imageData: newImage, type: .jpeg)) }
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
                                PostPreview(nrPost: nrPost, replyTo: replyTo, quotingEvent: quotingEvent, vm: vm, onDismiss: { onDismiss() })
                            }
                            .presentationBackgroundCompat(themes.theme.background)
                        }
                        else {
                            NBNavigationStack {
                                PostPreview(nrPost: nrPost, replyTo: replyTo, quotingEvent: quotingEvent, vm: vm, onDismiss: { onDismiss() })
                            }
                            .presentationBackgroundCompat(themes.theme.background)
                        }
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
                                self.vm.typingTextModel.pastedImages.append(
                                    PostedImageMeta(
                                        index: self.vm.typingTextModel.pastedImages.count,
                                        imageData: imageData,
                                        type: .jpeg
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
