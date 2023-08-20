//
//  NewPostModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI
import Combine

public final class NewPostModel: ObservableObject {
    
    @Published var mentioning = false
    @Published var text: String = ""
    @Published var pastedImages:[UIImage] = []
    @Published var debouncedText: String = ""
    @Published var term: String = ""
    @Published var nEvent:NEvent?
    @Published var lastHit:String = "NOHIT"
    @Published var textView:SystemTextView?
    
    @Published var uploading = false
    @Published var uploadError:String?
    @Published var selectedMentions:[Contact] = []
    @Published var previewNRPost:NRPost?
    private var subscriptions = Set<AnyCancellable>()
    @Published var gifSheetShown = false
    
    @Published var contactSearchResults:[Contact] = []
    
    var filteredContactSearchResults:[Contact] {
        guard let wot = NosturState.shared.wot else {
            // WoT disabled, just following before non-following
            return contactSearchResults
                .sorted(by: { NosturState.shared.followingPublicKeys.contains($0.pubkey) && !NosturState.shared.followingPublicKeys.contains($1.pubkey) })
        }
        return contactSearchResults
            // WoT enabled, so put in-WoT before non-WoT
            .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
            // Put following before non-following
            .sorted(by: { NosturState.shared.followingPublicKeys.contains($0.pubkey) && !NosturState.shared.followingPublicKeys.contains($1.pubkey) })
    }
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewPostModel.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(named: "AccentColor")!),
            TextFormattingRule(fontTraits: .traitBold)
        ]),
        HighlightRule(pattern: NewPostModel.typingRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(named: "AccentColor")!),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let typingRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|(?<![/\\?])#)", options: [])
    static let mentionRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\w+|(?<![/\\?])#\\S+)", options: [])
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
    
    public func sendNow(replyTo:Event? = nil, quotingEvent:Event? = nil, dismiss:DismissAction) {
        if (!pastedImages.isEmpty) {
            uploading = true
            
            uploadImages(images: pastedImages)
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
                    if (self.pastedImages.count == urls.count) {
                        self._sendNow(urls:urls, pastedImages: self.pastedImages, replyTo:replyTo, quotingEvent:quotingEvent, dismiss:dismiss)
                    }
                })
                .store(in: &subscriptions)
        }
        else {
            self._sendNow(urls:[], pastedImages: pastedImages, replyTo:replyTo, quotingEvent:quotingEvent, dismiss:dismiss)
        }
    }
    
    private func _sendNow(urls:[String], pastedImages:[UIImage], replyTo:Event? = nil, quotingEvent:Event? = nil, dismiss:DismissAction) {
        guard let account = NosturState.shared.account else { return }
        guard account.privateKey != nil else { NosturState.shared.readOnlyAccountSheetShown = true; return }
        let publicKey = account.publicKey
        var nEvent = nEvent ?? NEvent(content: "")
        nEvent.createdAt = NTimestamp.init(date: Date())
        
        if !pastedImages.isEmpty && urls.count > 0 {
            // send message with images
            for url in urls {
                nEvent.content += "\n\(url)"
            }
        }
        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
        nEvent = applyMentionsNip08(nEvent, bumpIndex: quotingEvent != nil)
        nEvent = putHashtagsInTags(nEvent)
        
        if let quotingEvent {
            nEvent.content = nEvent.content + "\n#[0]"
            nEvent.tags.insert(NostrTag(["e", quotingEvent.id, "", "mention"]), at: 0)
        }
        
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }

        
        let cancellationId = UUID()
        if account.isNC {
            nEvent.publicKey = publicKey
            nEvent = nEvent.withId()
            
            // Save unsigned event:
            DataProvider.shared().bg.perform {
                let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned")
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    sendNotification(.newPostSaved, savedEvent)
                }
                DataProvider.shared().bgSave()
                
                DispatchQueue.main.async {
                    NosturState.shared.nsecBunker?.requestSignature(forEvent: nEvent, whenSigned: { signedEvent in
                        DataProvider.shared().bg.perform {
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
        else if let signedEvent = try? NosturState.shared.signEvent(nEvent) {
            DataProvider.shared().bg.perform {
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
            DataProvider.shared().bg.perform {
                let replyToId = replyTo.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
                }
            }
        }
        if let quotingEvent {
            DispatchQueue.main.async {
                sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: quotingEvent.id))
            }
        }
        dismiss()
    }
    
    public func showPreview(quotingEvent:Event? = nil) {
        guard let account = NosturState.shared.account else { return }
        var nEvent = nEvent ?? NEvent(content: "")
        
        nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected:selectedMentions)
        nEvent = applyMentionsNip08(nEvent, bumpIndex: quotingEvent != nil)
        nEvent = putHashtagsInTags(nEvent)
        nEvent.publicKey = account.publicKey
        
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        for index in pastedImages.indices {
            nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
        }
        
        if let quotingEvent {
            nEvent.content = nEvent.content + "\n\n#[0]"
            nEvent.tags.insert(NostrTag(["e", quotingEvent.id, "", "mention"]), at: 0)
        }
        
        DataProvider.shared().bg.perform {
            let previewEvent = createPreviewEvent(nEvent)
            if (!self.pastedImages.isEmpty) {
                previewEvent.previewImages = self.pastedImages
            }
            let nrPost = NRPost(event: previewEvent, isPreview: true)
            DispatchQueue.main.async {
                self.previewNRPost = nrPost
            }
            DataProvider.shared().bg.delete(previewEvent)
        }
    }
    
    public func selectContactSearchResult(_ contact:Contact) {
        guard textView != nil else { return }
        let mentionName = contact.handle
        text = "\(text.dropLast(term.count))\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063}"
        selectedMentions.append(contact)
        mentioning = false
        lastHit = mentionName
        term = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
//            vm.mentioning = false
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
    }
    
    private func searchContacts(_ mentionTerm:String) {
        guard let account = NosturState.shared.account else { return }
        let fr = Contact.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)]
        fr.predicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), account.blockedPubkeys_)
        
        contactSearchResults = Array(((try? DataProvider.shared().viewContext.fetch(fr)) ?? []).prefix(60))
    }
}
