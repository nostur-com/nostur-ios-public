//
//  NewNote.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import SwiftUI
import Combine

public final class NewNoteText: ObservableObject {
    
    @Published var mentioning = false
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    @Published var term: String = ""
    @Published var nEvent:NEvent?
    @Published var lastHit:String = "NOHIT"
    @Published var textView:SystemTextView?
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewNoteText.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(named: "AccentColor")!),
            TextFormattingRule(fontTraits: .traitBold)
        ])
   ]
    static let mentionRegex = try! NSRegularExpression(pattern: "(@\\w+)", options: [])
    private var bag = Set<AnyCancellable>()

    public init(dueTime: TimeInterval = 0.2) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &bag)
    }
}



struct NewNote: View {
    let PLACEHOLDER = "What's happening?"
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    @Binding var noteCancellationId:UUID?
    
    @StateObject var vm = NewNoteText()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)], predicate: NSPredicate(value: false))
    var contacts:FetchedResults<Contact>
    var firstResults:[Contact] { Array(contacts.prefix(30)) }
    
    @State var tapOrFirstResults:[Contact] = []
    
    var body: some View {
        VStack {
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
//                        print(signedEvent.wrappedEventJson())
                        up.publishNow(signedEvent)
//                        noteCancellationId = up.publish(signedEvent)
                        dismiss()
                    }
                } label: {
                    Text("Post")
                }
                .buttonStyle(.borderedProminent)
                .cornerRadius(20)
            }
            
            
            HStack(alignment: .top) {
                ProfilePicView(pubkey: ns.account!.publicKey, account: ns.account!)
                
                ZStack(alignment:.leading) {
                    VStack(alignment: .leading) {
                        Text(PLACEHOLDER).foregroundColor(.gray)
                            .offset(x: 5.0, y: 7.0)
                            .opacity(vm.text == "" ? 1 : 0)
                        Spacer()
                    }
                    VStack(alignment: .leading) {
                        HighlightedTextEditor(text: $vm.text, shouldBecomeFirstResponder: true, highlightRules: NewNoteText.rules)
                        // optional modifiers
                            .onCommit { print("commited") }
                            .onEditingChanged {
                                
                            }
//                            .onTextChange { print("latest text value", $0) }
                            .onSelectionChange { (range: NSRange) in
                                print(range)
                            }
                            .introspect { editor in
                                if (vm.textView == nil) {
                                    vm.textView = editor.textView
                                    vm.textView?.backgroundColor = UIColor.clear
                                }
//                                editor.textView.becomeFirstResponder()
                            }
                            .frame(minHeight: 200, idealHeight: 325, maxHeight: 550, alignment: .top)
                        Spacer()
                    }
                }
            }
            if vm.mentioning {
                ScrollView {
                    LazyVStack {
                        ForEach(firstResults) { contact in
                            ContactSearchResultRow(contact: contact) {
                                print("WHAT")
                                guard vm.textView != nil else { return }
                                print("OKEEE")
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
        .padding(10)
        .onChange(of: firstResults) { newResults in
            guard let firstResult = newResults.first else { return }
            tapOrFirstResults.append(firstResult)
        }
        .onChange(of: vm.debouncedText) { mentionString in
//            let mentionStringTrimmed = mentionString.trimmingCharacters(in: .whitespacesAndNewlines)
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
                textToReplaceWithNpubs = textToReplaceWithNpubs.replacingOccurrences(of: contact.username, with: contact.npub, options: .caseInsensitive)
            }
            if (vm.nEvent == nil) {
                vm.nEvent = NEvent(content: textToReplaceWithNpubs)
            } else {
                vm.nEvent!.content = textToReplaceWithNpubs
            }
            
        }
    }
}

struct NewNote_Previews: PreviewProvider {
    @State static var noteCancellationId:UUID?
    static var previews: some View {
        NewNote(noteCancellationId: $noteCancellationId)
            .withPreviewEnvironment()
    }
}

func mentionTerm(_ text:String) -> String? {
    if let rangeStart = text.lastIndex(of: Character("@")) {
        let extractedString = String(text[rangeStart..<text.endIndex].dropFirst(1))
        return extractedString
    }
    return nil
}
