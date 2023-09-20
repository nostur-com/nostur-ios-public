//
//  DMConversationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI
import Algorithms

struct DMConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme:Theme
    @Namespace private var bottom
    
    @EnvironmentObject var la:LoggedInAccount
    
    private let recentDM:Event
    private let pubkey:String
    private let theirPubkey:String?
    private let dateHeaderFormatter:DateFormatter
    
    @State private var text:String = ""
    @State private var didLoad = false
    
    @FetchRequest
    private var theirs:FetchedResults<Event>
    
    @FetchRequest
    private var mine:FetchedResults<Event>
    
    private var messages:[Event] {
        chain(theirs,mine)
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
    private var messagesByDay:[Date: [Event]] {
        let calendar = Calendar.current
        
        return Dictionary(grouping: messages) { event in
            calendar.startOfDay(for: event.date)
        }
    }
    
    private var contact:Contact? {
        guard let rootDM = rootDM else { return nil }
        // contact is in .pubkey or in .firstP (depending on incoming/outgoing DM.
        // if there are multiple P's, we try lastP if firstP is same as pubkey (edge case)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP(), firstP != self.pubkey  {
            return rootDM.contacts?.first(where: { $0.pubkey == firstP })
        }
        else if rootDM.pubkey == self.pubkey, let lastP = rootDM.lastP(), lastP != self.pubkey  {
            return rootDM.contacts?.first(where: { $0.pubkey == lastP })
        }
        else {
            return rootDM.contact
        }
    }
    
    private var contactPubkey:String? {
        guard let rootDM = rootDM else { return nil }
        // pubkey is .pubkey or .firstP (depending on incoming/outgoing DM.)
        // if there are multiple P's, we try lastP if firstP is same as pubkey (edge case)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP(), firstP != self.pubkey {
            return firstP
        }
        else if rootDM.pubkey == self.pubkey, let lastP = rootDM.lastP(), lastP != self.pubkey {
            return lastP
        }
        else {
            return rootDM.pubkey
        }
    }
    
    private var rootDM:Event? {
        allMessagesSorted.first
    }
    
    private var isAccepted:Bool {
        // if possible infer accepted by checking if we responded (mine)
        conv.accepted || (!mine.isEmpty)
    }
    
    private var allMessagesSorted:[Event] {
        chain(theirs, mine).sorted(by: { $0.created_at < $1.created_at })
    }

    @ObservedObject private var conv:Conversation
    
    init(recentDM:Event, pubkey:String, conv:Conversation) {
        self.conv = conv
        self.pubkey = pubkey
        self.recentDM = recentDM
        self.theirPubkey = recentDM.pubkey != pubkey
        ? recentDM.pubkey
        : recentDM.firstP()
        self.dateHeaderFormatter = DateFormatter()
        self.dateHeaderFormatter.dateStyle = .short
        
        let theirs = Event.fetchRequest()
        
        theirs.predicate = NSPredicate(
            format: "kind == 4 AND pubkey == %@ AND tagsSerialized CONTAINS %@", theirPubkey ?? "ERROR", serializedP(pubkey))
        theirs.fetchLimit = 500
        theirs.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _theirs = FetchRequest(fetchRequest: theirs)
        
        let mine = Event.fetchRequest()
        mine.predicate = NSPredicate(
            format: "kind == 4 AND pubkey == %@ AND tagsSerialized CONTAINS %@", pubkey, serializedP(theirPubkey ?? "ERROR"))
        mine.fetchLimit = 500
        mine.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _mine = FetchRequest(fetchRequest: mine)
    }
    
    var body: some View {
        if theirPubkey != nil {
            ScrollViewReader { proxy in
                ScrollView {
                    if !messagesByDay.keys.isEmpty {
                        LazyVStack(pinnedViews: [.sectionFooters]) {
                            Section {
                                VStack {
                                    ForEach(messagesByDay.keys.sorted(by: { $0 < $1 }), id:\.self) { date in
                                        if let messages = messagesByDay[date] {
                                            VStack {
                                                Text(dateHeaderFormatter.string(from: date))
                                                    .font(.caption).foregroundColor(.gray)
                                                    .padding(.top, 15)
                                                ForEach(messages.sorted(by: { $0.created_at < $1.created_at })) { event in
                                                    BalloonView(message: event.noteText,
                                                                isSentByCurrentUser: event.pubkey == pubkey)
                                                    .id(event.id)
                                                }
                                            }
                                            .id(date)
                                        }
                                    }
                                    Group {
                                        if isAccepted {
                                            ChatInputField(message: $text) {
                                                // Create and send DM (via unpublisher?)
                                                guard let pk = la.account.privateKey else { NRState.shared.readOnlyAccountSheetShown = true; return }
                                                guard let theirPubkey = self.theirPubkey else { return }
                                                var nEvent = NEvent(content: text)
                                                if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                                    nEvent.content = replaceNsecWithHunter2(nEvent.content)
                                                }
                                                nEvent.kind = .directMessage
                                                guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
                                                    L.og.error("🔴🔴 Could encrypt content")
                                                    return
                                                }
                                                
                                                nEvent.content = encrypted
                                                nEvent.tags.append(NostrTag(["p", theirPubkey]))
                                                
                                                
                                                if let signedEvent = try? la.account.signEvent(nEvent) {
                                                    //                        print(signedEvent.wrappedEventJson())
                                                    Unpublisher.shared.publishNow(signedEvent)
                                                    //                        noteCancellationId = up.publish(signedEvent)
                                                    text = ""
                                                }
                                            }
                                        }
                                        else if rootDM != nil {
                                            Divider()
                                            Button(String(localized:"Accept message request", comment:"Button to accept a Direct Message request")) {
                                                conv.accepted = true
                                                bg().perform {
                                                    conv.dmState.accepted = true
                                                    conv.dmState.didUpdate.send()
                                                    DataProvider.shared().bgSave()
                                                    DispatchQueue.main.async {
                                                        DirectMessageViewModel.default.reloadAccepted()
                                                    }
                                                }
                                            }
                                            .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    Color.clear.frame(height: 25)
                                        .id(bottom)
                                }
                            }
                            header: {
                                if let contactPubkey {
                                    VStack {
                                        PFP(pubkey: contactPubkey, contact: contact, size: 100)
                                            .onTapGesture { navigateTo(ContactPath(key: contactPubkey)) }
                                        //                        ProfileBadgesContainer(pubkey: contactPubkey)
                                        
                                        if let contact = contact {
                                            HStack(spacing:1) {
                                                Text("\(contact.anyName) ").font(.headline)
                                                if contact.couldBeImposter == 1 {
                                                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                                        .padding(.horizontal, 8)
                                                        .background(.red)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(8)
                                                        .padding(.top, 3)
                                                        .layoutPriority(2)
                                                }
                                                else if let nip05 = contact.nip05, contact.nip05veried {
                                                    NostrAddress(nip05: nip05)
                                                }
                                            }
                                            if (contact.followsYou()) {
                                                Text("Follows you", comment: "Label that shows if someone is following you").font(.system(size: 12))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary)
                                                    .opacity(0.7)
                                                    .cornerRadius(13)
                                            }
                                            
                                            Text("\n**\(contact.followingPubkeys.count)** Following", comment: "Text that shows how many people this account follows")
                                            
                                            
                                            HStack {
                                                Menu {
                                                    Button {
                                                        UIPasteboard.general.string = contactPubkey
                                                    } label: {
                                                        Label(String(localized:"Copy public key hex", comment:"Menu action to copy to a contacts public key in hex format to clipboard"), systemImage: "doc.on.clipboard")
                                                    }
                                                    Button {
                                                        UIPasteboard.general.string = Contact.npub(contactPubkey)
                                                    } label: {
                                                        Label(String(localized:"Copy npub", comment:"Menu action to copy a contacts public key in npub format to clipboard"), systemImage: "doc.on.clipboard")
                                                    }
                                                    Button {
                                                        la.account.blockedPubkeys_ = la.account.blockedPubkeys_ + [contactPubkey]
                                                        sendNotification(.blockListUpdated, la.account.blockedPubkeys_)
                                                        dismiss()
                                                    } label: {
                                                        Label(
                                                            String(localized:"Block \(contact.anyName)", comment:"Menu action"), systemImage: "slash.circle")
                                                    }
                                                } label: {
                                                    Image(systemName: "person.badge.key.fill")
                                                }
                                                ContactPrivateNoteToggle(contact: contact)
                                                ProfileLightningButton(contact: contact)
                                            }
                                            
                                            Text("\n\(String(contact.about ?? ""))")
                                                .padding(10)
                                        }
                                        else {
                                            Text("@\(npub(contactPubkey))").foregroundColor(.secondary)
                                            HStack {
                                                Menu {
                                                    Button {
                                                        UIPasteboard.general.string = contactPubkey
                                                    } label: {
                                                        Label(String(localized:"Copy public key hex", comment:"Menu action to copy to a contacts public key in hex format to clipboard"), systemImage: "doc.on.clipboard")
                                                    }
                                                    Button {
                                                        UIPasteboard.general.string = Contact.npub(contactPubkey)
                                                    } label: {
                                                        Label(String(localized:"Copy npub", comment:"Menu action to copy a contacts public key in npub format to clipboard"), systemImage: "doc.on.clipboard")
                                                    }
                                                    Button {
                                                        la.account.blockedPubkeys_ = la.account.blockedPubkeys_ + [contactPubkey]
                                                        sendNotification(.blockListUpdated, la.account.blockedPubkeys_)
                                                        dismiss()
                                                    } label: {
                                                        Label(
                                                            String(localized:"Block \(String(contactPubkey.prefix(11)))", comment:"Menu action"), systemImage: "slash.circle")
                                                    }
                                                } label: {
                                                    Image(systemName: "person.badge.key.fill")
                                                }
                                            }
                                        }
                                    }
                                    .task {
                                        req(RM.getUserMetadata(pubkey: contactPubkey))
                                    }
                                }
                                else { EmptyView() }
                            }
                        }
                        .onAppear {
                            guard !didLoad else { return }
                            didLoad = true
                            guard let lastDay = messagesByDay.keys.sorted(by: { $0 < $1 }).last else { return }
                            guard (messagesByDay[lastDay]?.sorted(by: { $0.created_at < $1.created_at }).last) != nil else { return }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                proxy.scrollTo(bottom)
                            }
                        }
                        .onAppear {
                            if (contact == nil) {
                                if let contactPubkey {
                                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: contactPubkey)))
                                }
                            }
                        }
                        .onAppear {
                            // Update lastSeenDMCreatedAt, which updates unread count
                            if let root = allMessagesSorted.first {
                                
                                root.objectWillChange.send()
                                root.lastSeenDMCreatedAt = allMessagesSorted.last!.created_at
                                // Save context here? or on go to background
                                DataProvider.shared().save()
                            }
                        }
                        .onAppear {
                            // fix rootDM contacts missing?
                            // fix contacts
                            if let root = allMessagesSorted.first {
                                guard root.contacts?.count ?? 0 == 0 else { return }
                                
                                let vc = DataProvider.shared().viewContext
                                let cs = Contact.ensureContactsCreated(event: root.toNEvent(), context: vc)
                                root.objectWillChange.send()
                                root.addToContacts(NSSet(array: cs))
                                do {
                                    try vc.save()
                                }
                                catch {
                                    L.og.error("DMConversationsView: \(error)")
                                }
                            }
                        }
                    }
                }
            }
//            .padding(.bottom, 20)
            .navigationTitle("\(contact?.authorName ?? String(localized:"DM", comment:"Navigation title for a DM conversation screen (Direct Message)"))")
            .task {
                // TODO: CHANGE TO REALTIME DM SUBSCRIPTION
                guard let theirPubkey = self.theirPubkey else {
                    L.og.error("🔴🔴 Could not find contact pubkey (theirPubkey)")
                    return
                }
                req(RM.getDMConversation(pubkey: pubkey, theirPubkey: theirPubkey))
            }
        }
        else {
            Text("Error: could not find contact pubkey", comment: "Error shown on DM conversation screen")
                .centered()
        }
    }
}
//
//struct Previews_DMConversationView_Previews: PreviewProvider {
//    static var previews: some View {
//        
//        PreviewContainer({ pe in pe.loadDMs() }) {
//            NavigationStack {
//                let preston = "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204"
//                let recentDM = PreviewFetcher.fetchEvent("96500cec51f30a7bee4bf15984f574550064913ec8d00e164e9efad34a989236")
//                if let recent = recentDM {
//                    DMConversationView(recentDM: recent, pubkey: preston)
//                }
//            }
//        }
//    }
//}
//
//

