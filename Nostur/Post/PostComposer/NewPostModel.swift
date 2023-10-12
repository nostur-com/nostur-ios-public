//
//  NewPostModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI
import Combine

public final class TypingTextModel: ObservableObject {
    @Published var text: String = ""
    @Published var pastedImages:[UIImage] = []
    @Published var selectedMentions:Set<Contact> = [] // will become p-tags in the final post
    private var subscriptions = Set<AnyCancellable>()
}

public final class NewPostModel: ObservableObject {
    public var typingTextModel = TypingTextModel()
    private var mentioning = false
    @Published var showMentioning = false // To reduce rerendering, use this flag instead of (vm.mentioning && !vm.filteredContactSearchResults.isEmpty)
    private var term: String = ""
    var nEvent:NEvent?
    var lastHit:String = "NOHIT"
    var textView:SystemTextView?
    
    @Published var sending = false
    @Published var uploading = false
    @Published var uploadError:String?
    var requiredP:String? = nil
    @Published var availableContacts:Set<Contact> = [] // are available to toggle on/off for notifications
    
    @Published var previewNRPost:NRPost?
    @Published var gifSheetShown = false
    
    @Published var contactSearchResults:[Contact] = []
    @Published var activeAccount:Account? = nil
    
    private var subscriptions = Set<AnyCancellable>()
    
    public init(dueTime: TimeInterval = 0.2) {
        self.typingTextModel.$text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.textChanged(value)
            })
            .store(in: &subscriptions)
    }
    
    var filteredContactSearchResults:[Contact] {
        let wot = WebOfTrust.shared
        if WOT_FILTER_ENABLED() {
            return contactSearchResults
                // WoT enabled, so put in-WoT before non-WoT
                .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                // Put following before non-following
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
        else {
            // WoT disabled, just following before non-following
            return contactSearchResults
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
    }
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewPostModel.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Theme.default.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ]),
        HighlightRule(pattern: NewPostModel.typingRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Theme.default.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let typingRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|(?<![/\\?])#)", options: [])
    static let mentionRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\w+|(?<![/\\?])#\\S+)", options: [])
    
    public func sendNow(replyTo:Event? = nil, quotingEvent:Event? = nil, dismiss:DismissAction) {
        if (!typingTextModel.pastedImages.isEmpty) {
            uploading = true
            
            uploadImages(images: typingTextModel.pastedImages)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { result in
                    switch result {
                        case .failure(let error):
                        L.og.error("Error uploading images: \(error.localizedDescription)")
                        self.uploadError = "Image upload error"
                        sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                        L.og.debug("All images uploaded successfully")
                    }
                }, receiveValue: { urls in
                    if (self.typingTextModel.pastedImages.count == urls.count) {
                        self._sendNow(urls:urls, pastedImages: self.typingTextModel.pastedImages, replyTo:replyTo, quotingEvent:quotingEvent, dismiss: dismiss)
                    }
                })
                .store(in: &subscriptions)
        }
        else {
            self._sendNow(urls:[], pastedImages: typingTextModel.pastedImages, replyTo:replyTo, quotingEvent:quotingEvent, dismiss: dismiss)
        }
    }
    
    private func _sendNow(urls:[String], pastedImages:[UIImage], replyTo:Event? = nil, quotingEvent:Event? = nil, dismiss:DismissAction) {
        guard let account = activeAccount else { return }
        guard isFullAccount(account) else { showReadOnlyMessage(); return }
        let publicKey = account.publicKey
        var nEvent = nEvent ?? NEvent(content: "")
        nEvent.createdAt = NTimestamp.init(date: Date())
        
        if !pastedImages.isEmpty && urls.count > 0 {
            // send message with images
            for url in urls {
                nEvent.content += "\n\(url)"
            }
        }
        // @mentions to nostr:npub
        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: typingTextModel.selectedMentions)
        
        // #hashtags to .t tags
        nEvent = putHashtagsInTags(nEvent)
        
        // always include the .p of pubkey we are replying to (not required by spec, but more healthy for nostr)
        if let requiredP = requiredP {
            nEvent.tags.append(NostrTag(["p", requiredP]))
        }

        // Include .p tags for @mentions
        let selectedPtags = typingTextModel.selectedMentions
            .filter { $0.pubkey != requiredP } // don't include requiredP twice
            .map { NostrTag(["p", $0.pubkey]) }
        
        nEvent.tags.append(contentsOf: selectedPtags)
        
        // If we are quote reposting, include the quoted post as nostr:note1 at the end
        // TODO: maybe at .q tag, need to look up if there is a spec
        if let quotingEvent {
            if let note1id = note1(quotingEvent.id) {
                nEvent.content = (nEvent.content + "\nnostr:" + note1id)
            }
            nEvent.tags.insert(NostrTag(["e", quotingEvent.id, "", "mention"]), at: 0)
            
            if !nEvent.pTags().contains(quotingEvent.pubkey) { // TODO: Add notification toggles to turn off
                nEvent.tags.append(NostrTag(["p", quotingEvent.pubkey]))
            }
        }
        
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }

        
        let cancellationId = UUID()
        if account.isNC {
            nEvent.publicKey = publicKey
            nEvent = nEvent.withId()
            
            // Save unsigned event:
            bg().perform {
                let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned")
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    sendNotification(.newPostSaved, savedEvent)
                }
                DataProvider.shared().bgSave()
                
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                        bg().perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = "awaiting_send"
                            savedEvent.cancellationId = cancellationId
                            savedEvent.updateNRPost.send(savedEvent)
                            DispatchQueue.main.async {
                                _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                            }
                        }
                    })
                }
            }
        }
        else if let signedEvent = try? account.signEvent(nEvent) {
            bg().perform {
                let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send")
                savedEvent.cancellationId = cancellationId
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if nEvent.kind == .reaction {
                    do {
                        try Event.updateReactionTo(savedEvent, context: DataProvider.shared().bg) // TODO: Revert this on 'undo'
                    } catch {
                        L.og.error("🦋🦋🔴🔴🔴 problem updating Like relation .id \(nEvent.id)")
                    }
                }
                
                DataProvider.shared().bgSave()
                if ([1,6,9802,30023].contains(savedEvent.kind)) {
                    DispatchQueue.main.async {
                        sendNotification(.newPostSaved, savedEvent)
                    }
                }
            }
            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
        }
        
        if let replyTo {
            bg().perform {
                let replyToNEvent = replyTo.toNEvent()
                let replyToId = replyTo.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
                    // Republish post being replied to
                    Unpublisher.shared.publishNow(replyToNEvent)
                }
            }
        }
        if let quotingEvent {
            bg().perform {
                let quotingNEvent = quotingEvent.toNEvent()
                let quotingEventId = quotingEvent.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: quotingEventId))
                    // Republish post being quoted
                    Unpublisher.shared.publishNow(quotingNEvent)
                }
            }
        }
        dismiss()
        sendNotification(.didSend)
    }
    
    public func showPreview(quotingEvent:Event? = nil) {
        guard let account = activeAccount else { return }
        var nEvent = nEvent ?? NEvent(content: "")
        nEvent.publicKey = account.publicKey
        
        // @mentions to nostr:npub
        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: typingTextModel.selectedMentions)

        // #hashtags to .t tags
        nEvent = putHashtagsInTags(nEvent)
        
        // Also include .p tags other @mentions
        let selectedPtags = typingTextModel.selectedMentions.map { NostrTag(["p", $0.pubkey]) }
        nEvent.tags.append(contentsOf: selectedPtags)
        
        // If we are quote reposting, include the quoted post as nostr:note1 at the end
        // TODO: maybe at .q tag, need to look up if there is a spec
        if let quotingEvent {
            if let note1id = note1(quotingEvent.id) {
                nEvent.content = (nEvent.content + "\nnostr:" + note1id)
            }
            nEvent.tags.insert(NostrTag(["e", quotingEvent.id, "", "mention"]), at: 0)
            
            if !nEvent.pTags().contains(quotingEvent.pubkey) { 
                nEvent.tags.append(NostrTag(["p", quotingEvent.pubkey]))
            }
        }

        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        
        for index in typingTextModel.pastedImages.indices {
            nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
        }
    
        
        bg().perform {
            let previewEvent = createPreviewEvent(nEvent)
            if (!self.typingTextModel.pastedImages.isEmpty) {
                previewEvent.previewImages = self.typingTextModel.pastedImages
            }
            let nrPost = NRPost(event: previewEvent, isPreview: true)
            DispatchQueue.main.async {
                self.previewNRPost = nrPost
            }
            bg().delete(previewEvent)
        }
    }
    
    public func selectContactSearchResult(_ contact:Contact) {
        guard textView != nil else { return }
        let mentionName = contact.handle
        typingTextModel.text = "\(typingTextModel.text.dropLast(term.count))\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} "
        availableContacts.insert(contact)
        typingTextModel.selectedMentions.insert(contact)
        mentioning = false
        lastHit = mentionName
        term = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
            let newPosition = self.textView!.endOfDocument
            self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
        }
    }
    
    public func textChanged(_ newText:String) {
        if (nEvent == nil) {
            nEvent = NEvent(content: newText)
        } else {
            nEvent!.content = newText
        }
        
        if let mentionTerm = mentionTerm(newText) {
            if mentionTerm == lastHit {
                mentioning = false
            }
            else {
                mentioning = true
                term = mentionTerm
                self.searchContacts(mentionTerm)
            }
            
        }
        else {
            mentioning = false
        }
        
        let showMentioning = mentioning && !filteredContactSearchResults.isEmpty
        if showMentioning != self.showMentioning { // check first to reduce rerendering
            self.showMentioning = showMentioning
        }
    }
    
    private func searchContacts(_ mentionTerm:String) {
        guard let account = account() else { return }
        let fr = Contact.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)]
        fr.predicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), account.blockedPubkeys_)
        
        let contactSearchResults = Array(((try? DataProvider.shared().viewContext.fetch(fr)) ?? []).prefix(60))
        
        // check first to reduce rerendering, if both are already empty, don't re-set it.
        if self.contactSearchResults.isEmpty && contactSearchResults.isEmpty {
            return
        }
        self.contactSearchResults = contactSearchResults
    }
    
    public func loadQuotingEvent(_ quotingEvent:Event) {
        var newQuoteRepost = NEvent(content: "")
        newQuoteRepost.kind = .textNote
        nEvent = newQuoteRepost
    }
    
    public func loadReplyTo(_ replyTo:Event) {
        var newReply = NEvent(content: "")
        newReply.kind = .textNote
        guard let replyTo = replyTo.toMain() else {
            L.og.error("🔴🔴 Problem getting event from viewContext")
            return
        }
        let existingPtags = TagsHelpers(replyTo.tags()).pTags()
        let availableContacts = Set(Contact.fetchByPubkeys(existingPtags.map { $0.pubkey }, context: DataProvider.shared().viewContext))
        requiredP = replyTo.contact?.pubkey
        self.availableContacts = Set([replyTo.contact].compactMap { $0 } + availableContacts)
        typingTextModel.selectedMentions = Set([replyTo.contact].compactMap { $0 } + availableContacts)
        
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

        nEvent = newReply
    }
    
    public func directMention(_ contact:Contact) {
        guard textView != nil else { return }
        let mentionName = contact.handle
        typingTextModel.text = "@\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} "
        availableContacts.insert(contact)
        typingTextModel.selectedMentions.insert(contact)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
            let newPosition = self.textView!.endOfDocument
            self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
        }
    }
}

func mentionTerm(_ text:String) -> String? {
    if let rangeStart = text.lastIndex(of: Character("@")) {
        let extractedString = String(text[rangeStart..<text.endIndex].dropFirst(1))
        return extractedString
    }
    return nil
}
