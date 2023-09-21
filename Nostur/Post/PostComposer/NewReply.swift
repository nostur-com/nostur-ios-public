//
//  NewReply.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import Combine

struct NewReply: View {
    @EnvironmentObject private var theme:Theme
    let PLACEHOLDER = String(localized:"Enter your reply", comment: "Placeholder when typing a reply")
    
    var replyTo:Event
    @Namespace private var textfield
    @Namespace private var images
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var vm = NewPostModel()
    @StateObject private var ipm = ImagePickerModel()
    
    @State private var replyToNRPost:NRPost?
    @State private var textHeight:CGFloat = 0
    
    var body: some View {
        VStack(spacing:0) {
            if let account = vm.activeAccount, let replyToNRPost {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            PostRowDeletable(nrPost: replyToNRPost, hideFooter: true)
                                .onTapGesture { }
                                .disabled(true)
                            HStack(spacing:0) {
                                NewReplyingToFragment(contact: replyToNRPost.contact, pubkey: replyToNRPost.pubkey)
                                    .offset(x:70)
                                Spacer()
                            }
                            HStack(alignment: .top, spacing: 0) {
                                PostAccountSwitcher(activeAccount: account, onChange: { account in
                                    vm.activeAccount = account
                                })
                                .padding(.horizontal, 10)
                                HighlightedTextEditor(
                                    text: $vm.text,
                                    pastedImages: $vm.pastedImages,
                                    shouldBecomeFirstResponder: true,
                                    highlightRules: NewPostModel.rules,
                                    photoPickerTapped: {
                                        ipm.photoPickerShown = true
                                    },
                                    gifsTapped: {
                                        vm.gifSheetShown = true
                                    })
                                .introspect { editor in
                                    if (vm.textView == nil) {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                            vm.textView = editor.textView
                                        }
                                    }
                                }
                                .frame(height: textHeight)
                                .id(textfield)
                                .photosPicker(isPresented: $ipm.photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                                .onChange(of: ipm.newImage) { newImage in
                                    if let newImage {
                                        vm.pastedImages.append(newImage)
                                        textHeight = 200
                                        withAnimation {
                                            proxy.scrollTo(images, anchor: .bottom)
                                        }
                                    }
                                }
                                .background(alignment:.topLeading) {
                                    Text(PLACEHOLDER).foregroundColor(.gray)
                                        .opacity(vm.text == "" ? 1 : 1)
                                        .offset(x: 5.0, y: 4.0)
                                }
                                .sheet(isPresented: $vm.gifSheetShown) {
                                    NavigationStack {
                                        GifSearcher { gifUrl in
                                            vm.text += gifUrl + "\n"
                                        }
                                    }
                                    .presentationBackground(theme.background)
                                }
                                AnyStatus(filter: "NewPost")
                            }
                            HStack {
                                ImagePreviews(pastedImages: $vm.pastedImages)
                                    .padding(.leading, DIMENSIONS.ROW_PFP_SPACE)
                            }
                            .id(images)
                            .padding(.bottom, 100) // Need some extra space for expanding account switcher
                        }
                    }
                    .onAppear {
                        textHeight = 300
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                proxy.scrollTo(textfield)
                            }
                        }
                    }
                }
                .padding(10)
                .onChange(of: vm.debouncedText) { newText in
                    vm.textChanged(newText)
                }
                .onAppear {
                    var newReply = NEvent(content: "")
                    newReply.kind = .textNote
                    DataProvider.shared().bg.perform {
                        if let replyTo = replyTo.toMain() {
                            DispatchQueue.main.async {
                                let root = TagsHelpers(replyTo.tags()).replyToRootEtag()
                                
                                if (root != nil) { // ADD "ROOT" + "REPLY"
                                    let newRootTag = NostrTag(["e", root!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
                                    newReply.tags.append(newRootTag)
                                    
                                    let newReplyTag = NostrTag(["e", replyTo.id, "", "reply"])
                                    
                                    newReply.tags.append(newReplyTag)
                                }
                                else { // ADD ONLY "ROOT"
                                    let newRootTag = NostrTag(["e", replyTo.id, "", "root"])
                                    newReply.tags.append(newRootTag)
                                }
                                
                                let rootA = replyTo.toNEvent().replyToRootAtag()
                                
                                if (rootA != nil) { // ADD EXISTING "ROOT" (aTag) FROM REPLYTO
                                    let newRootATag = NostrTag(["a", rootA!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
                                    newReply.tags.append(newRootATag)
                                }
                                else if replyTo.kind == 30023 { // ADD ONLY "ROOT" (aTag) (DIRECT REPLY TO ARTICLE)
                                    let newRootTag = NostrTag(["a", replyTo.aTag, "", "root"]) // TODO RECOMMENDED RELAY HERE
                                    newReply.tags.append(newRootTag)
                                }
                                
                                
                                // ADD ALL "P" TAGS
                                let existingPtags = TagsHelpers(replyTo.tags()).pTags()
                                newReply.tags.append(contentsOf: existingPtags)
                                
                                // TODO: DEDUPLICATE P TAGS
                                
                                // ADD PUBKEY OF REPLYING TO EVENT
                                let replyToPtag = NostrTag(["p", replyTo.pubkey])
                                
                                newReply.tags.append(replyToPtag)
                                vm.nEvent = newReply
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss() // TODO: If wrote something, confirm cancellation
                        } label: {
                            Text("Cancel")
                        }
                    }
                    
                    if let uploadError = vm.uploadError {
                        ToolbarItem(placement: .principal) {
                            Text(uploadError).foregroundColor(.red)
                        }
                    }
                    
                    if IS_CATALYST {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                ipm.photoPickerShown = true
                            } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)

                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                vm.gifSheetShown = true
                            } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(vm.uploading)

                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                            vm.showPreview()
                        }
                        .buttonStyle(.borderless)
                        .disabled(vm.uploading)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            vm.sendNow(replyTo: replyTo, dismiss:dismiss)
                        } label: {
                            if (vm.uploading) {
                                ProgressView()
                            }
                            else {
                                Text("Post.verb", comment: "Button to post (publish) a new post")
                            }
                        }
                        .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        .cornerRadius(20)
                        .disabled(vm.uploading || vm.text.isEmpty)
                    }
                }
                .sheet(item: $vm.previewNRPost) { nrPost in
                    NavigationStack {
                        PostPreview(nrPost: nrPost, sendNow: {
                            vm.sendNow(replyTo: replyTo, dismiss:dismiss) }, uploading: $vm.uploading)
                    }
                    .presentationBackground(theme.background)
                }
                
                if vm.mentioning && !vm.filteredContactSearchResults.isEmpty {
                    ScrollView {
                        LazyVStack {
                            ForEach(vm.filteredContactSearchResults) { contact in
                                ContactSearchResultRow(contact: contact, onSelect: {
                                    vm.selectContactSearchResult(contact)
                                })
                            }
                        }
                    }
                    .padding()
                }
            }
            else {
                ProgressView()
            }
        }
        .onAppear {
            vm.activeAccount = account()
        }
        .task {
            bg().perform {
                let replyToNRPost = NRPost(event: replyTo)
                DispatchQueue.main.async {
                    self.replyToNRPost = replyToNRPost
                }
            }
        }
    }
}

struct NewReplyingToFragment: View {
    @EnvironmentObject var theme: Theme
    var contact:NRContact?
    var pubkey:String
    
    var body: some View {
        HStack(spacing:1) {
            Text("Replying to ")
                .foregroundColor(theme.secondary)
                .font(.system(size: 13))
                .fontWeight(.light)
            Group {
                if let contact {
                    Text("@\(contact.anyName)")
                }
                else {
                    Text("@\(String(pubkey.prefix(5)))")
                }
            }
            .foregroundColor(theme.accent)
            .font(.system(size: 13))
            .fontWeight(.light)
        }
    }
}

struct NewReply_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let event = PreviewFetcher.fetchEvent() {
                    NewReply(replyTo: event)
                }
            }
        }
    }
}
