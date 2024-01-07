//
//  ComposePost15.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2024.
//

import SwiftUI
import NavigationBackport

struct ComposePost15: View {
    public var replyTo:Event? = nil
    public var quotingEvent:Event? = nil
    public var directMention:Contact? = nil // For initiating a post from profile view
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var themes:Themes
    @Environment(\.dismiss) public var dismissCompose
    
    @StateObject private var vm = NewPostModel()
    @State private var gifSheetShown = false
    @State private var photoPickerShown = false
    @State private var cameraSheetShown = false
    
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
                                    PostRowDeletable(nrPost: replyToNRPost, hideFooter: true, connect: .bottom, theme: themes.theme)
                                        .onTapGesture { }
                                        .disabled(true)
                                }
                                
                                HStack(alignment: .top) {
                                    PostAccountSwitcher(activeAccount: account, onChange: { account in
                                        vm.activeAccount = account
                                    }).equatable()
                                    
                                    Entry(vm: vm, photoPickerShown: $photoPickerShown, gifSheetShown: $gifSheetShown, cameraSheetShown: $cameraSheetShown, replyTo: replyTo, quotingEvent: quotingEvent, directMention: directMention, dismiss: dismissCompose)
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
                            .padding(10)
//                            .toolbar {
//                                
//                            }
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
                            PostPreview(nrPost: nrPost, replyTo: replyTo, quotingEvent: quotingEvent, vm: vm, onDismiss: { dismissCompose() })
                        }
                        .presentationBackgroundCompat(themes.theme.background)
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
            ConnectionPool.shared.connectAllWrite()
        }
    }
}
