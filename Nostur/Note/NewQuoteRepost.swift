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
    @EnvironmentObject var up:Unpublisher
//    @Binding var noteCancellationId:UUID?
    
//    @State var newReplyEvent:NEvent
    
    @StateObject var vm = NewNoteText()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    
    @State var tapOrFirstResults:[Contact] = []
    
    init(quotingEvent:Event) {
        self.quotingEvent = quotingEvent
    }
    
    var body: some View {
        if ns.account != nil {
            VStack {
                ScrollView {
                    HStack(alignment: .top) {
                        ProfilePicView(pubkey: ns.account!.publicKey, account: ns.account!)
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
                                MinimalQuotedNoteFragment(event: quotingEvent)
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
                                        vm.text = vm.text.dropLast(vm.term.count) + contact.username
                                        tapOrFirstResults.append(contact)
                                        vm.mentioning = false
                                        vm.lastHit = contact.username
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
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button {
                            dismiss() // TODO: If wrote something, confirm cancellation
                        } label: {
                            Text("Cancel")
                        }
                        Spacer()
                        Button {
                            guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                            guard var nEvent = vm.nEvent else { return }
                            
                            nEvent = applyMentionsNip08(nEvent, bumpIndex: true)
                                nEvent.content = nEvent.content + "\n#[0]"
                            nEvent.tags.insert(NEventTag.event(otherEventId: quotingEvent.id, type: "mention"), at: 0)
//                            nEvent.content = noteText
//
//                            nEvent = applyMentionsNip08(nEvent)
                            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                nEvent.content = replaceNsecWithHunter2(nEvent.content)
                            }
                            if let signedEvent = try? ns.signEvent(nEvent) {
//                                let _ = up.publish(signedEvent)
//                                print(signedEvent.wrappedEventJson())
                                up.publishNow(signedEvent)
                                dismiss()
                            }
                        } label: {
                            Text("Post")
                        }
                        .buttonStyle(.borderedProminent)
                        .cornerRadius(20)
                    }//.background(Color("BackgroundColor"))
                }
            }
            .padding(10)
            .onChange(of: firstResults) { newResults in
                guard let firstResult = newResults.first else { return }
                tapOrFirstResults.append(firstResult)
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
                
                var textToReplaceWithNpubs = vm.text
                for contact in tapOrFirstResults {
                    textToReplaceWithNpubs = textToReplaceWithNpubs.replacingOccurrences(of: "@\(contact.username)", with: "@\(contact.npub)", options: .caseInsensitive)
                }
                vm.nEvent!.content = textToReplaceWithNpubs
            }
            .onAppear {
                var newQuoteRepost = NEvent(content: "")
                newQuoteRepost.kind = .textNote
                vm.nEvent = newQuoteRepost
            }
        }
        else {
            ProgressView()
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

