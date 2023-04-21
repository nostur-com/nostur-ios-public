//
//  NewQuoteRepost.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import SwiftUI
import Combine

struct NewQuoteRepost: View {
    let PLACEHOLDER = "Add comment"
    var quotingEvent:Event
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    @StateObject var vm = NewNoteText()
    @StateObject var ipm = ImagePickerModel()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    
    @State var selectedMentions:[Contact] = []
    @State var previewEvent:Event?
    @State var uploading = false
    @State var uploadError:String?
    @State var subscriptions = Set<AnyCancellable>()
    
    init(quotingEvent:Event) {
        self.quotingEvent = quotingEvent
    }
    
    var body: some View {
        if ns.account != nil {
            VStack {
                ScrollView {
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
                                .onSelectionChange { (range: NSRange) in
                                    print(range)
                                }
                                .introspect { editor in
                                    if (vm.textView == nil) {
                                        vm.textView = editor.textView
                                    }
                                }
                                .frame(minHeight: 50, maxHeight: 500)
                                .onChange(of: ipm.newImage) { newImage in
                                    if let newImage {
                                        vm.pastedImages.append(newImage)
                                    }
                                }
                                ImagePreviews(pastedImages: $vm.pastedImages)
                                if let quotedVPost = quotingEvent.toVPost() {
                                    QuotedNoteFragmentView(vPost: quotedVPost)
                                        .frame(minHeight: 250, maxHeight: 500)
                                }
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
                    }
                    Spacer()
                }
            }
            .padding(10)
            .onAppear {
                updateEventWithNewText()
            }
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
                var newQuoteRepost = NEvent(content: "")
                newQuoteRepost.kind = .textNote
                vm.nEvent = newQuoteRepost
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss() // TODO: If wrote something, confirm cancellation
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
                        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
                        nEvent = putHashtagsInTags(nEvent)
                        nEvent.publicKey = account.publicKey
                        for index in vm.pastedImages.indices {
                            nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
                        }
                        nEvent.content = nEvent.content + "\n\n#[0]"
                        nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        let previewEvent = createPreviewEvent(nEvent)
                        if (vm.pastedImages.count > 0) {
                            previewEvent.previewImages = vm.pastedImages
                        }
                        self.previewEvent = previewEvent
                    }
                    .cornerRadius(20)
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
    
    func updateEventWithNewText() {
        if (vm.nEvent == nil) {
            vm.nEvent = NEvent(content: replaceMentionsWithHandles(vm.text, selected: selectedMentions))
        } else {
            vm.nEvent!.content = replaceMentionsWithHandles(vm.text, selected: selectedMentions)
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
                        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: selectedMentions)
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
                        nEvent = putHashtagsInTags(nEvent)
                        
                        for url in urls {
                            nEvent.content += "\n\(url)"
                        }
                        nEvent.content = nEvent.content + "\n#[0]"
                        nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        if let signedEvent = try? ns.signEvent(nEvent) {
                            //            let _ = up.publish(signedEvent)
                            //            print(signedEvent.wrappedEventJson())
                            //            quotingEvent.reposted = true
                            // .needsviewupdate?
                            up.publishNow(signedEvent)
//                            sendNotification(.viewNeedsUpdate)
                            dismiss()
                            previewEvent = nil
                        }
                    }
//                    print("Uploaded image URLs: \(urls)")
                })
                .store(in: &subscriptions)
            
        }
        else {

            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: selectedMentions)
            nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
            nEvent = putHashtagsInTags(nEvent)
            nEvent.content = nEvent.content + "\n#[0]"
            nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                nEvent.content = replaceNsecWithHunter2(nEvent.content)
            }
            if let signedEvent = try? ns.signEvent(nEvent) {
                //            let _ = up.publish(signedEvent)
                //            print(signedEvent.wrappedEventJson())
                //            quotingEvent.reposted = true
                // .needsviewupdate?
                up.publishNow(signedEvent)
//                sendNotification(.viewNeedsUpdate)
                dismiss()
                previewEvent = nil
            }
        }
    }
}

struct NewQuoteRepost_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        
        let event = PreviewFetcher.fetchEvent("c3a040feac185585f984147cdaf7a7ec5774b06db29ff25017c45026e470daeb")
        
        if (event != nil) {
            NewQuoteRepost(quotingEvent:event!)
                .withPreviewEnvironment()
        }
    }
}

