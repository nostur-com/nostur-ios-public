//
//  DMConversationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI
import Algorithms

struct DMConversationView: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var up:Unpublisher
    let nav:NavigationModel = .shared
    @ObservedObject var rootDM:Event
    let pubkey:String
    let theirPubkey:String?
    let dateHeaderFormatter:DateFormatter
    
    @State var text:String = ""
    
    @FetchRequest
    var theirs:FetchedResults<Event>
    
    @FetchRequest
    var mine:FetchedResults<Event>
    
    var messagesVPosts:[VPost] {
        (Array(theirs) + Array(mine))
            .sorted(by: { $0.created_at < $1.created_at })
            .map(VPostTransformer.shared.toVPost)
    }
    
    var messagesByDay:[Date: [VPost]] {
        let calendar = Calendar.current

        return Dictionary(grouping: messagesVPosts) { vPost in
            calendar.startOfDay(for: vPost.event.date)
        }
    }
    
    var contact:Contact? {
        // contact is in .pubkey or in .firstP (depending on incoming/outgoing DM.
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP() {
            return rootDM.contacts?.first(where: { $0.pubkey == firstP })
        }
        else {
            return rootDM.contact
        }
    }
    
    var contactPubkey:String {
        // pubkey is .pubkey or .firstP (depending on incoming/outgoing DM.)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP() {
            return firstP
        }
        else {
            return rootDM.pubkey
        }
    }
    
    var isAccepted:Bool {
        // if possible infer accepted by checking if we responded (mine)
        (contact?.dmAccepted ?? false) || (mine.count > 0)
    }
    
    var allMessagesSorted:[Event] {
        chain(theirs, mine).sorted(by: { $0.created_at < $1.created_at })
    }
    
    init(rootDM:Event, pubkey:String) {
        self.pubkey = pubkey
        self.rootDM = rootDM
        self.theirPubkey = rootDM.pubkey != pubkey
            ? rootDM.pubkey
            : rootDM.firstP()
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
                    if messagesByDay.keys.count > 0 {
                        LazyVStack(pinnedViews: [.sectionFooters]) {
                            Section {
                                ForEach(messagesByDay.keys.sorted(by: { $0 < $1 }), id:\.self) { date in
                                    if let messages = messagesByDay[date] {
                                        Text(dateHeaderFormatter.string(from: date))
                                            .font(.caption).foregroundColor(.gray)
                                            .padding(.top, 15)
                                        ForEach(messages.sorted(by: { $0.event.created_at < $1.event.created_at })) { message in
                                            BalloonView(message: message.event.noteText,
                                                        isSentByCurrentUser: message.event.pubkey == pubkey)
                                            .id(message.event.id)
                                            .onTapGesture {
                                                UIPasteboard.general.string = message.event.toNEvent().eventJson()
                                                // fix contacts
                                                let vc = DataProvider.shared().viewContext
                                                let cs = Contact.ensureContactsCreated(event: message.event.toNEvent(), context: vc)
                                                message.event.addToContacts(NSSet(array: cs))
                                                do {
                                                    try vc.save()
                                                }
                                                catch {
                                                    print(error)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        header: {
                                VStack {
                                    PFP(pubkey: contactPubkey, pictureUrl: contact?.picture, size: 100)
                                        .onTapGesture { nav.navigateTo(ContactPath(key: contactPubkey)) }
                                    //                        ProfileBadgesContainer(pubkey: contactPubkey)
                                    
                                    if let contact = contact {
                                        HStack(spacing:1) {
                                            Text("\(contact.authorName) ").font(.headline)
                                            if (contact.nip05veried) {
                                                Group {
                                                    Image(systemName: "checkmark.seal.fill")
                                                    Text(contact.nip05domain).font(.footnote)
                                                }.foregroundColor(.blue)
                                            }
                                        }
                                        
                                        HStack {
                                            Text("@\(contact.username)").foregroundColor(.secondary)
                                        }
                                        
                                        if (ns.followsYou(contact)) {
                                            Text("Follows you").font(.system(size: 12))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary)
                                                .opacity(0.7)
                                                .cornerRadius(13)
                                        }
                                        
                                        Text("\n**\(contact.followingPubkeys.count)** Following")
                                        
                                        
                                        HStack {
                                            Menu {
                                                Button {
                                                    UIPasteboard.general.string = contactPubkey
                                                } label: {
                                                    Label("Copy public key hex \(String(contactPubkey.prefix(11)))...", systemImage: "doc.on.clipboard")
                                                }
                                                Button {
                                                    UIPasteboard.general.string = Contact.npub(contactPubkey)
                                                } label: {
                                                    Label("Copy npub \(String(Contact.npub(contactPubkey).prefix(11)))...", systemImage: "doc.on.clipboard")
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
                                                    Label("Copy public key hex \(String(contactPubkey.prefix(11)))...", systemImage: "doc.on.clipboard")
                                                }
                                                Button {
                                                    UIPasteboard.general.string = Contact.npub(contactPubkey)
                                                } label: {
                                                    Label("Copy npub \(String(Contact.npub(contactPubkey).prefix(11)))...", systemImage: "doc.on.clipboard")
                                                }
                                            } label: {
                                                Image(systemName: "person.badge.key.fill")
                                            }
                                        }
                                    }
                                }
                                .task {
                                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndBadges(pubkey: contactPubkey)))
                                }
                            }
                        footer: {
                                Group {
                                    if isAccepted {
                                        ChatInputField(message: $text) {
                                            // Create and send DM (via unpublisher?)
                                            guard let pk = ns.account?.privateKey else { ns.readOnlyAccountSheetShown = true; return }
                                            guard let theirPubkey = self.theirPubkey else { return }
                                            var nEvent = NEvent(content: text)
                                            if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                                nEvent.content = replaceNsecWithHunter2(nEvent.content)
                                            }
                                            nEvent.kind = .directMessage
                                            guard let encrypted = NKeys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
                                                print("🔴🔴 Could encrypt content")
                                                return
                                            }
                                            
                                            nEvent.content = encrypted
                                            nEvent.tags.append(NEventTag(type: "p", otherInformation: theirPubkey))
                                            
                                            
                                            if let signedEvent = try? ns.signEvent(nEvent) {
                                                //                        print(signedEvent.wrappedEventJson())
                                                up.publishNow(signedEvent)
                                                //                        noteCancellationId = up.publish(signedEvent)
                                                text = ""
                                            }
                                        }
                                    }
                                    else {
                                        Divider()
                                        Button("Accept message request") {
                                            if let contact = contact {
                                                contact.dmAccepted = true // Save context here or onAppclose..
                                            }
                                            else {
                                                var newContact = Contact(context: DataProvider.shared().viewContext)
                                                newContact.pubkey = contactPubkey
                                                newContact.metadata_created_at = 0
                                                newContact.updated_at = 0
                                                newContact.dmAccepted = true
                                                // objectWillChange?
                                                rootDM.contact = newContact
                                                // sp fetch info..
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(.vertical, 10)
                            }
                        }
                        .onAppear {
                            guard let lastDay = messagesByDay.keys.sorted(by: { $0 < $1 }).last else { return }
                            guard let lastMessage = messagesByDay[lastDay]?.sorted(by: { $0.event.created_at < $1.event.created_at }).last else { return }
                                
                            proxy.scrollTo(lastMessage.id)
                        }
                        .onAppear {
                            if (contact == nil) {
                                SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: contactPubkey)))
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
                    }
                }
            }
            .padding(.bottom, 20)
            .navigationTitle("\(contact?.authorName ?? "DM")")
            .task {
                // TODO: CHANGE TO DM SUBSCRIPTION
                guard let theirPubkey = self.theirPubkey else {
                    print("🔴🔴 Could not find contact pubkey (theirPubkey)")
                    return
                }
                SocketPool.shared
                    .sendMessage(
                        ClientMessage(
                            type: .REQ,
                            message: RequestMessage
                                .getDMConversation(pubkey: pubkey, theirPubkey: theirPubkey)))
            }
        }
        else {
            Text("Error: could not find contact pubkey")
                .centered()
        }
    }
}

struct Previews_DMConversationView_Previews: PreviewProvider {
    static var previews: some View {
        
        let preston = "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204"
        let rootDM = PreviewFetcher.fetchEvent("96500cec51f30a7bee4bf15984f574550064913ec8d00e164e9efad34a989236")
        if let root = rootDM {
            NavigationStack {
                DMConversationView(rootDM: root, pubkey: preston)
                    .withPreviewEnvironment()
            }
        }
    }
}



