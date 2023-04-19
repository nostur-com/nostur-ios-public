//
//  NewReply.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import Combine

struct NewReply: View {
    let PLACEHOLDER = "Enter your reply"
    
    var replyTo:Event
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
//    @Binding var noteCancellationId:UUID?
    
//    @State var newReplyEvent:NEvent
    
    @StateObject var vm = NewNoteText()
    @StateObject var ipm = ImagePickerModel()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    @State var tapOrFirstResults:[Contact] = []
    @State var previewEvent:Event?
    @State var uploading = false
    @State var uploadError:String?
    @State var subscriptions = Set<AnyCancellable>()
    
//    init(replyTo:Event, noteCancellationId:Binding<UUID?>) {
    init(replyTo:Event) {
        self.replyTo = replyTo
//        _noteCancellationId = noteCancellationId
    }
    
    var body: some View {
        if ns.account != nil {
            VStack {
                ScrollView {
                    NoteRow(vPost: replyTo.toVPost()!, hideFooter: true)
                    HStack {
                        NewReplyingToFragment(contact: replyTo.contact, pubkey: replyTo.pubkey)
                            .offset(x:80)
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        PFP(pubkey: ns.account!.publicKey, pictureUrl: ns.account?.picture)
                            .padding(.horizontal, 10)
                        ZStack(alignment:.leading) {
                            VStack(alignment: .leading) {
                                Text(PLACEHOLDER).foregroundColor(.gray)
                                    .opacity(vm.text == "" ? 1 : 0)
                                    .offset(x: 5.0, y: 7.0)
                                Spacer()
                            }
                            VStack(alignment: .leading) {
                                HighlightedTextEditor(
                                    text: $vm.text,
                                    pastedImages: $vm.pastedImages,
                                    shouldBecomeFirstResponder: true,
                                    highlightRules: NewNoteText.rules,
                                    photoPickerTapped: {
                                        ipm.photoPickerShown = true
                                    })
                                    .frame(minHeight: 100, idealHeight: 125, maxHeight: 250, alignment: .top)
                                    .photosPicker(isPresented: $ipm.photoPickerShown, selection: $ipm.imageSelection, matching: .images, photoLibrary: .shared())
                                    .onChange(of: ipm.newImage) { newImage in
                                        if let newImage {
                                            vm.pastedImages.append(newImage)
                                        }
                                    }
                                ImagePreviews(pastedImages: $vm.pastedImages)
                                Spacer()
                            }
                        }
                    }
                    
                    
                    if vm.mentioning {
                        ScrollView {
                            LazyVStack {
                                ForEach(firstResults) { contact in
                                    ContactSearchResultRow(contact: contact) {
                                        guard vm.textView != nil else { return }
                                        let mentionName = contact.handle
                                        vm.text = vm.text.dropLast(vm.term.count) + mentionName
                                        tapOrFirstResults.append(contact)
                                        vm.mentioning = false
                                        vm.lastHit = mentionName
                                        vm.term = ""
                                        
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { // after 0.02 sec to get the new .endOfDocument
        //                                    self.vm.mentioning = false
                                            let newPosition = vm.textView!.endOfDocument
                                            vm.textView!.selectedTextRange = vm.textView!.textRange(from: newPosition, to: newPosition)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
            .padding(10)
            .onAppear {
                updateEventWithNewText()
            }
            .onChange(of: firstResults) { newResults in
                guard newResults.count > 0 else { return }
                if let exactResult = newResults.first(where: { $0.handle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == vm.term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    tapOrFirstResults.insert(exactResult, at:0)
                    updateEventWithNewText()
                }
            }
            .onChange(of: vm.debouncedText) { mentionString in
                guard let account = ns.account else { return }
                
                if let mentionTerm = mentionTerm(mentionString) {
                    print ("mentionTerm \(mentionTerm) lastHit: \(vm.lastHit)")

                    if mentionTerm == vm.lastHit {
                        vm.mentioning = false
                    }
                    else {
                        vm.mentioning = true
                        vm.term = mentionTerm
                        contacts.nsPredicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm, mentionTerm, account.blockedPubkeys_)
                    }
                }
                else {
                    vm.mentioning = false
                }
                
                updateEventWithNewText()
            }
            .onAppear {
                var newReply = NEvent(content: "")
                newReply.kind = .textNote
                
                let root = TagsHelpers(replyTo.tags()).replyToRootEtag()
                
                if (root != nil) { // ADD "ROOT" + "REPLY"
                    let newRootTag = NEventTag(type: "e", otherInformation: root!.otherInformation[0], "", "root") // TODO RECOMMENDED RELAY HERE
                    newReply.tags.append(newRootTag)
                    
                    let newReplyTag = NEventTag(type: "e", otherInformation: replyTo.id, "", "reply")
                    
                    newReply.tags.append(newReplyTag)
                }
                else { // ADD ONLY "ROOT"
                    let newRootTag = NEventTag(type: "e", otherInformation: replyTo.id, "", "root")
                    newReply.tags.append(newRootTag)
                }
                
                // ADD ALL "P" TAGS
                let existingPtags = TagsHelpers(replyTo.tags()).pTags()
                newReply.tags.append(contentsOf: existingPtags)
                
                // TODO: DEDUPLICATE P TAGS
                
                // ADD PUBKEY OF REPLYING TO EVENT
                let replyToPtag = NEventTag(type: "p", otherInformation: replyTo.pubkey)
                
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
                
                ToolbarItem {
                    Button("Preview") {
                        guard let account = ns.account else { return }
                        guard var nEvent = vm.nEvent else { return }
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                        nEvent = putHashtagsInTags(nEvent)
                        nEvent.publicKey = account.publicKey
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        for index in vm.pastedImages.indices {
                            nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
                        }
                        let previewEvent = createPreviewEvent(nEvent)
                        if (vm.pastedImages.count > 0) {
                            previewEvent.previewImages = vm.pastedImages
                        }
                        self.previewEvent = previewEvent
                    }
                    .cornerRadius(20)
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
                            Text("Post")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .cornerRadius(20)
                    .disabled(uploading)
                }
            }
            .sheet(item: $previewEvent) { previewEvent in
                NavigationStack {
                    PostPreview(previewEvent: previewEvent, sendNow: self.sendNow)
                        .onDisappear {
                            DataProvider.shared().viewContext.delete(previewEvent)
                        }
                }
            }
        }
        else {
            ProgressView()
        }
    }
    
    // Replaces "@handles in text with @npubs", which will later be replaced with #[index], and in a future update with nostr:..
    func updateEventWithNewText() {
        var textToReplaceWithNpubs = vm.text
        for contact in tapOrFirstResults.sorted(by: { $0.handle.count > $1.handle.count }) { // .count so we replace @TestMacOS before partial match @test
            textToReplaceWithNpubs = textToReplaceWithNpubs.replacingOccurrences(of: "@\(contact.handle)", with: "@\(contact.npub)", options: .caseInsensitive)
        }
        if (vm.nEvent == nil) {
            vm.nEvent = NEvent(content: textToReplaceWithNpubs)
        } else {
            vm.nEvent!.content = textToReplaceWithNpubs
        }
    }
    
    func sendNow() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard var nEvent = vm.nEvent else { return }
        
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
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
                        nEvent = putHashtagsInTags(nEvent)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
                            up.publishNow(signedEvent)
                            dismiss()
                            previewEvent = nil
                        }
                    }
//                    print("Uploaded image URLs: \(urls)")
                })
                .store(in: &subscriptions)
            
            
        }
        else {
            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
            nEvent = putHashtagsInTags(nEvent)
            
            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                nEvent.content = replaceNsecWithHunter2(nEvent.content)
            }
            if let signedEvent = try? ns.signEvent(nEvent) {
                up.publishNow(signedEvent)
                dismiss()
                previewEvent = nil
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
                if (contact != nil) {
                    Text("@\(contact!.username)")
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
        
        let event = PreviewFetcher.fetchEvent("c3a040feac185585f984147cdaf7a7ec5774b06db29ff25017c45026e470daeb")
        
        if (event != nil) {
            NewReply(replyTo:event!)
                .withPreviewEnvironment()
        }
    }
}
