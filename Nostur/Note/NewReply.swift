//
//  NewReply.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI

struct NewReply: View {
    let PLACEHOLDER = "Enter your reply"
    
    var replyTo:Event
    
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
    
//    init(replyTo:Event, noteCancellationId:Binding<UUID?>) {
    init(replyTo:Event) {
        self.replyTo = replyTo
//        _noteCancellationId = noteCancellationId
    }
    
    var body: some View {
        if ns.account != nil {
            VStack {
                ScrollView {
                    NoteRow(vPost: replyTo.toVPost(), hideFooter: true)
                    HStack {
                        NewReplyingToFragment(contact: replyTo.contact, pubkey: replyTo.pubkey)
                            .offset(x:80)
                        Spacer()
                    }
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
                                    .frame(minHeight: 100, idealHeight: 125, maxHeight: 250, alignment: .top)
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
                                        let mentionName = contact.username != "" ? contact.username : contact.npub
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
                            
                            nEvent = applyMentionsNip08(nEvent, bumpIndex: false)
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
//                vm.nEvent = applyMentionsNip08(vm.nEvent!)
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
        }
        else {
            ProgressView()
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
