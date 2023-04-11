//
//  NewQuoteRepost.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/03/2023.
//

import SwiftUI

struct NewQuoteRepost: View {
    let PLACEHOLDER = "Add comment"
    
    var quotingEvent:Event
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
//    @Binding var noteCancellationId:UUID?
    
//    @State var newReplyEvent:NEvent
    
    @StateObject var vm = NewNoteText()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    
    @State var tapOrFirstResults:[Contact] = []
    @State var previewEvent:Event?
    
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
                                HighlightedTextEditor(text: $vm.text, shouldBecomeFirstResponder: true, highlightRules: NewNoteText.rules)
                                // optional modifiers
                                    .onCommit { print("commited") }
                                    .onEditingChanged {
                                        
                                    }
//                                    .onTextChange { print("latest text value", $0) }
                                    .onSelectionChange { (range: NSRange) in
                                        print(range)
                                    }
                                    .introspect { editor in
                                        if (vm.textView == nil) {
                                            vm.textView = editor.textView
                                            vm.textView?.backgroundColor = UIColor.clear
                                        }
                                    }
                                    .frame(minHeight: 50, maxHeight: 500)
//                                    .frame(minHeight: 60, idealHeight: 175, maxHeight: 250, alignment: .top)
//                                QuoteById(id: quotingEvent.id)
                                QuotedNoteFragmentView(vPost: quotingEvent.toVPost()!)
//                                MinimalQuotedNoteFragment(vPost: quotingEvent.toVPost()!)
                                    .frame(minHeight: 250, maxHeight: 500)
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
                ToolbarItem {
                    Button("Preview") {
                        guard let account = ns.account else { return }
                        guard var nEvent = vm.nEvent else { return }
                        nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
                        nEvent = putHashtagsInTags(nEvent)
                        nEvent.publicKey = account.publicKey
                        nEvent.content = nEvent.content + "\n\n#[0]"
                        nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
                        
                        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                            nEvent.content = replaceNsecWithHunter2(nEvent.content)
                        }
                        self.previewEvent = createPreviewEvent(nEvent)
                    }
                    .cornerRadius(20)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Post") { sendNow() }
                    .buttonStyle(.borderedProminent)
                    .cornerRadius(20)
                }
            }
            .sheet(item: $previewEvent) { previewEvent in
                NavigationStack {
                    PostPreview(previewEvent: previewEvent, sendNow: self.sendNow)
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
        
        nEvent = putHashtagsInTags(nEvent)
        nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
        nEvent.content = nEvent.content + "\n#[0]"
        nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        if let signedEvent = try? ns.signEvent(nEvent) {
//            let _ = up.publish(signedEvent)
//            print(signedEvent.wrappedEventJson())
            quotingEvent.reposted = true
            // .needsviewupdate?
            up.publishNow(signedEvent)
            sendNotification(.viewNeedsUpdate)
            dismiss()
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

