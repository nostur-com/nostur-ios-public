import SwiftUI
import Combine

struct NewReply: View {
    let PLACEHOLDER = "Enter your reply"
    
    var replyTo:Event
    @Namespace var textfield
    @Namespace var images
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    
    @StateObject var vm = NewNoteText()
    @StateObject var ipm = ImagePickerModel()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    @State var selectedMentions:[Contact] = []
    @State var replyToNRPost:NRPost?
    @State var previewNRPost:NRPost?
    @State var uploading = false
    @State var uploadError:String?
    @State var subscriptions = Set<AnyCancellable>()
    @State var gifSheetShown = false
    @State var textHeight:CGFloat = 0
    
    var body: some View {
        VStack(spacing:0) {
            if let account = ns.account, let replyToNRPost {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            PostRowDeletable(nrPost: replyToNRPost, hideFooter: true)
                            HStack(spacing:0) {
                                NewReplyingToFragment(contact: replyTo.contact, pubkey: replyTo.pubkey)
                                    .offset(x:70)
                                Spacer()
                            }
                            HStack(alignment: .top, spacing: 0) {
                                PFP(pubkey: account.publicKey, account: account)
                                    .padding(.horizontal, 10)
                                HighlightedTextEditor(
                                    text: $vm.text,
                                    pastedImages: $vm.pastedImages,
                                    shouldBecomeFirstResponder: true,
                                    highlightRules: NewNoteText.rules,
                                    photoPickerTapped: {
                                        ipm.photoPickerShown = true
                                    },
                                    gifsTapped: {
                                        gifSheetShown = true
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
                                .sheet(isPresented: $gifSheetShown) {
                                    NavigationStack {
                                        GifSearcher { gifUrl in
                                            vm.text += gifUrl + "\n"
                                        }
                                    }
                                }
                                AnyStatus(filter: "NewPost")
                            }
                            HStack {
                                ImagePreviews(pastedImages: $vm.pastedImages)
                                    .padding(.leading, DIMENSIONS.ROW_PFP_SPACE)
                            }
                            .id(images)
                        }
                    }
                    .onAppear {
                        textHeight = 250
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                proxy.scrollTo(textfield)
                            }
                        }
                    }
                }
                .padding(10)
                .onChange(of: vm.debouncedText) { newText in
                    if (vm.nEvent == nil) {
                        vm.nEvent = NEvent(content: newText)
                    } else {
                        vm.nEvent!.content = newText
                    }
                    
                    guard let account = ns.account else { return }
                    if let mentionTerm = mentionTerm(newText) {
                        print ("mentionTerm \(mentionTerm) lastHit: \(vm.lastHit)")
                        
                        if mentionTerm == vm.lastHit {
                            vm.mentioning = false
                        }
                        else {
                            vm.mentioning = true
                            vm.term = mentionTerm
                            contacts.nsPredicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), account.blockedPubkeys_)
                        }
                        
                    }
                    else {
                        vm.mentioning = false
                    }
                }
                .onAppear {
                    var newReply = NEvent(content: "")
                    newReply.kind = .textNote
                    
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
                    
                    // ADD ALL "P" TAGS
                    let existingPtags = TagsHelpers(replyTo.tags()).pTags()
                    newReply.tags.append(contentsOf: existingPtags)
                    
                    // TODO: DEDUPLICATE P TAGS
                    
                    // ADD PUBKEY OF REPLYING TO EVENT
                    let replyToPtag = NostrTag(["p", replyTo.pubkey])
                    
                    newReply.tags.append(replyToPtag)
                    vm.nEvent = newReply
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss() // TODO: If wrote something, confirm cancellation
                        } label: {
                            Text("Cancel")
                        }
                    }
                    
                    if let uploadError {
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
                            .disabled(uploading)

                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                gifSheetShown = true
                            } label: {
                                Image("GifButton")
                            }
                            .buttonStyle(.borderless)
                            .disabled(uploading)

                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized:"Preview", comment:"Preview button when creating a new post")) {
                            guard let account = ns.account else { return }
                            guard var nEvent = vm.nEvent else { return }
                            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
                            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                            nEvent = putHashtagsInTags(nEvent)
                            nEvent.publicKey = account.publicKey
                            
                            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                nEvent.content = replaceNsecWithHunter2(nEvent.content)
                            }
                            for index in vm.pastedImages.indices {
                                nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
                            }
                            DataProvider.shared().bg.perform {
                                let previewEvent = createPreviewEvent(nEvent)
                                if (vm.pastedImages.count > 0) {
                                    previewEvent.previewImages = vm.pastedImages
                                }
                                let previewNRPost = NRPost(event: previewEvent)
                                DispatchQueue.main.async {
                                    self.previewNRPost = previewNRPost
                                }
                                DataProvider.shared().bg.delete(previewEvent)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(uploading)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            sendNow()
                        } label: {
                            if (uploading) {
                                ProgressView()
                            }
                            else {
                                Text("Post.verb", comment: "Button to post (publish) a new post")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .cornerRadius(20)
                        .disabled(uploading || vm.text.isEmpty)
                    }
                }
                .sheet(item: $previewNRPost) { nrPost in
                    NavigationStack {
                        PostPreview(nrPost: nrPost, sendNow: self.sendNow, uploading: $uploading)
                        //                        .onDisappear {
                        //                            DataProvider.shared().viewContext.delete(previewEvent)
                        //                        }
                    }
                }
                
                if vm.mentioning && firstResults.count > 0 {
                    ScrollView {
                        LazyVStack {
                            ForEach(firstResults) { contact in
                                ContactSearchResultRow(contact: contact) {
                                    guard vm.textView != nil else { return }
                                    let mentionName = contact.handle
                                    vm.text = "\(vm.text.dropLast(vm.term.count))\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063}"
                                    selectedMentions.append(contact)
                                    vm.mentioning = false
                                    vm.lastHit = mentionName
                                    vm.term = ""
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // after 0.3 sec to get the new .endOfDocument
                                        //                                    self.vm.mentioning = false
                                        let newPosition = vm.textView!.endOfDocument
                                        vm.textView!.selectedTextRange = vm.textView!.textRange(from: newPosition, to: newPosition)
                                    }
                                }
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
        .task {
            DataProvider.shared().bg.perform {
                if let replyToBG = replyTo.toBG() {
                    let replyToNRPost = NRPost(event: replyToBG)
                    DispatchQueue.main.async {
                        self.replyToNRPost = replyToNRPost
                    }
                }
            }
        }
    }
    
//    func updateEventWithNewText() {
//        if (vm.nEvent == nil) {
//            vm.nEvent = NEvent(content: replaceMentionsWithHandles(vm.text, selected: selectedMentions))
//        } else {
//            vm.nEvent!.content = replaceMentionsWithHandles(vm.text, selected: selectedMentions)
//        }
//    }
    
    func sendNow() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard var nEvent = vm.nEvent else { return }
        nEvent.createdAt = NTimestamp.init(date: Date())
        
        if (vm.pastedImages.count > 0) {
            uploading = true
            
            uploadImages(images: vm.pastedImages)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { result in
                    switch result {
                        case .failure(let error):
                            print("Error uploading images: \(error.localizedDescription)")
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                            print("All images uploaded successfully")
                    }
                }, receiveValue: { urls in
                    
                    if (vm.pastedImages.count == urls.count) {
                        // send message with images
                        for url in urls {
                            nEvent.content += "\n\(url)"
                        }
                        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: selectedMentions)
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                        nEvent = putHashtagsInTags(nEvent)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
                            up.publishNow(signedEvent)
                            sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyTo.id))
                            dismiss()
                        }
                    }
//                    print("Uploaded image URLs: \(urls)")
                })
                .store(in: &subscriptions)
            
            
        }
        else {
            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: selectedMentions)
            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
            nEvent = putHashtagsInTags(nEvent)
            
            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                nEvent.content = replaceNsecWithHunter2(nEvent.content)
            }
            if let signedEvent = try? ns.signEvent(nEvent) {
                up.publishNow(signedEvent)
                sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyTo.id))
                dismiss()
            }
        }
    }
}

struct NewReplyingToFragment: View {

    var contact:Contact?
    var pubkey:String
    
    var body: some View {
        HStack(spacing:1) {
            Text("Replying to ")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
                .fontWeight(.light)
            Group {
                if let contact {
                    Text("@\(contact.anyName)")
                }
                else {
                    Text("@\(String(pubkey.prefix(5)))")
                }
            }.foregroundColor(.accentColor)
                .font(.system(size: 13))
                .fontWeight(.light)
        }
    }
}

struct NewReply_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        
//        let id = "c3a040feac185585f984147cdaf7a7ec5774b06db29ff25017c45026e470daeb"
        NavigationStack {
            if let event = PreviewFetcher.fetchEvent() {
                NewReply(replyTo: event)
            }
        }
        .withPreviewEnvironment({ pe in
            pe.loadPosts()
        })
    }
}
