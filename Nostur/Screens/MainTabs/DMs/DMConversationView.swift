//
//  DMConversationView.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI
import Algorithms
import Combine
import NostrEssentials

// Do the flip flip.
// We need to start at the last received message (bottom)
// But SwiftUI cannot do that
// So we flip the List (.scaleEffect(x: 1, y: -1, anchor: .center))
// and then reverse the rows, and flip then also.
struct DMConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Namespace private var top
    
    @EnvironmentObject var la: LoggedInAccount
    
    private let recentDM: Event
    private let pubkey: String
    private let theirPubkey: String?
    private let dateHeaderFormatter: DateFormatter
    
    @State private var text: String = ""
    @State private var didLoad = false
    
    @FetchRequest
    private var theirs: FetchedResults<Event>
    
    @FetchRequest
    private var mine: FetchedResults<Event>
    
    private var messages: [Event] {
        chain(theirs,mine)
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
    private var messagesByDay: [Date: [Event]] {
        let calendar = Calendar.current
        
        return Dictionary(grouping: messages) { event in
            calendar.startOfDay(for: event.date)
        }
    }
    
    private var contact: Contact? {
        guard let rootDM = rootDM else { return nil }
        // contact is in .pubkey or in .firstP (depending on incoming/outgoing DM.
        // if there are multiple P's, we try lastP if firstP is same as pubkey (edge case)
        if rootDM.pubkey == self.pubkey, let firstP = rootDM.firstP(), firstP != self.pubkey  {
            return Contact.fetchByPubkey(firstP, context: context())
        }
        else if rootDM.pubkey == self.pubkey, let lastP = rootDM.lastP(), lastP != self.pubkey  {
            return Contact.fetchByPubkey(lastP, context: context())
        }
        else {
            return rootDM.contact
        }
    }
    
    private var contactPubkey: String? {
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
    
    private var rootDM: Event? {
        allMessagesSorted.first
    }
    
    private var isAccepted: Bool {
        // if possible infer accepted by checking if we responded (mine)
        conv.accepted || (!mine.isEmpty)
    }
    
    private var allMessagesSorted: [Event] {
        chain(theirs, mine).sorted(by: { $0.created_at < $1.created_at })
    }
    
    @ObservedObject private var conv: Conversation
    
    init(recentDM: Event, pubkey: String, conv: Conversation) {
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
            format: "kind IN {4,14} AND pubkey == %@ AND tagsSerialized CONTAINS %@", theirPubkey ?? "ERROR", serializedP(pubkey))
        theirs.fetchLimit = 500
        theirs.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _theirs = FetchRequest(fetchRequest: theirs)
        
        let mine = Event.fetchRequest()
        mine.predicate = NSPredicate(
            format: "kind IN {4,14} AND pubkey == %@ AND tagsSerialized CONTAINS %@", pubkey, serializedP(theirPubkey ?? "ERROR"))
        mine.fetchLimit = 500
        mine.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _mine = FetchRequest(fetchRequest: mine)
    }
    
    var body: some View {
        if theirPubkey != nil {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(messagesByDay.keys.sorted(by: { $0 > $1 }), id:\.self) { date in
                            if let messages = messagesByDay[date] {
                                VStack { // Used to be LazyVStack, but now crashes for unknown reasons if not VStack
                                    Text(dateHeaderFormatter.string(from: date))
                                        .font(.caption).foregroundColor(.gray)
                                        .padding(.top, 15)
                                    ForEach(messages.sorted(by: { $0.created_at < $1.created_at })) { event in
                                        NRBalloonView(event: event, isSentByCurrentUser: event.pubkey == pubkey, time: event.date.formatted(date: .omitted, time: .shortened))
                                        //                                                    BalloonView(message: event.noteText,
                                        //                                                                isSentByCurrentUser: event.pubkey == pubkey, time: event.date.formatted(date: .omitted, time: .shortened))
                                            .id(event.id)
                                            .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                                    }
                                }
                                .id(date)
                                .scaleEffect(y: -1, anchor: .center)
                            }
                        }
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        
                        
                        if let contactPubkey {
                            VStack(alignment: .center) {
                                PFP(pubkey: contactPubkey, contact: contact, size: 100)
                                    .onTapGesture { navigateTo(ContactPath(key: contactPubkey), context: containerID) }
                                
                                //                        ProfileBadgesContainer(pubkey: contactPubkey)
                                
                                if let contact = contact {
                                    HStack(spacing:1) {
                                        Text("\(contact.anyName) ").font(.headline)
                                        if let similarToPubkey = contact.similarToPubkey {
                                            Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                                .padding(.horizontal, 8)
                                                .background(.red)
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                                .padding(.top, 3)
                                                .layoutPriority(2)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    sendNotification(.showImposterDetails, ImposterDetails(pubkey: contact.pubkey, similarToPubkey: similarToPubkey))
                                                }
                                        }
                                        else if let nip05 = contact.nip05, contact.nip05veried {
                                            NostrAddress(nip05: nip05)
                                        }
                                    }
                                    
                                    CopyableTextView(text: contact.npub)
                                        .lineLimit(1)
                                    
                                    if (contact.followsYou()) {
                                        Text("Follows you", comment: "Label that shows if someone is following you").font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary)
                                            .opacity(0.7)
                                            .cornerRadius(13)
                                    }
                                    
                                    FollowedBy(pubkey: contactPubkey, alignment: .center, showZero: true)
                                        .frame(minHeight: 95.0)
                                        .padding(.vertical, 15)
                                    
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
                                                dismiss()
                                                block(pubkey: contactPubkey, name: contact.anyName)
                                            } label: {
                                                Label(
                                                    String(localized:"Block \(contact.anyName)", comment:"Menu action"), systemImage: "slash.circle")
                                            }
                                        } label: {
                                            Image(systemName: "person.badge.key.fill")
                                        }
                                        ContactPrivateNoteToggle(contact: contact)
                                        if let nrContact = conv.nrContact {
                                            ProfileLightningButton(nrContact: nrContact)
                                        }
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
                                                block(pubkey: contactPubkey, name: contact?.anyName)
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
                            .frame(maxWidth: .infinity)
                            .task {
                                req(RM.getUserMetadata(pubkey: contactPubkey))
                            }
                            .scaleEffect(x: 1, y: -1, anchor: .center)
                            .listRowInsets(.init())
                            .listRowSeparator(.hidden)
                            .listRowBackground(theme.listBackground)
                        }
                        Color.clear.frame(height: 1)
                            .id(top)
                            .listRowInsets(.init())
                            .listRowSeparator(.hidden)
                            .listRowBackground(theme.listBackground)
                        
                    }
                    .scrollContentBackgroundCompat(.hidden)
                    .listStyle(.plain)
//                    .padding(.top, 55)
                    .scaleEffect(y: -0.99, anchor: .center) // On iOS 26 y: -1 becomes blurry for no reason, so use -0.99 ¯\_(ツ)_/¯
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Group {
                            if isAccepted {
                                ChatInputField(message: $text) {
                                    // Create and send DM (via unpublisher?)
                                    guard let pk = la.account.privateKey else { AppSheetsModel.shared.readOnlySheetVisible = true; return }
                                    guard let theirPubkey = self.theirPubkey else { return }
                                    var nEvent = NEvent(content: text)
                                    if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
                                        nEvent.content = replaceNsecWithHunter2(nEvent.content)
                                    }
                                    nEvent.kind = .legacyDirectMessage
                                    guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
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
                                    conv.dmState.accepted = true
                                    conv.dmState.didUpdate.send()
                                    DataProvider.shared().saveToDiskNow(.viewContext)
                                    DirectMessageViewModel.default.reloadAccepted()
                                    
                                }
                                .buttonStyle(NRButtonStyle(style: .borderedProminent))
                            }
                        }
                        .padding(.vertical, 5)
                        .modifier {
                            if #available(iOS 26.0, *), IS_CATALYST {
                                $0.padding(.bottom, 50)
                            }
                            else {
                                $0
                            }
                        }
                        .background(theme.listBackground)
                    }
                    
//                    VStack(spacing: 0) {
//                        Spacer()
//                        Group {
//                            if isAccepted {
//                                ChatInputField(message: $text) {
//                                    // Create and send DM (via unpublisher?)
//                                    guard let pk = la.account.privateKey else { AppSheetsModel.shared.readOnlySheetVisible = true; return }
//                                    guard let theirPubkey = self.theirPubkey else { return }
//                                    var nEvent = NEvent(content: text)
//                                    if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
//                                        nEvent.content = replaceNsecWithHunter2(nEvent.content)
//                                    }
//                                    nEvent.kind = .directMessage
//                                    guard let encrypted = Keys.encryptDirectMessageContent(withPrivatekey: pk, pubkey: theirPubkey, content: nEvent.content) else {
//                                        L.og.error("🔴🔴 Could encrypt content")
//                                        return
//                                    }
//                                    
//                                    nEvent.content = encrypted
//                                    nEvent.tags.append(NostrTag(["p", theirPubkey]))
//                                    
//                                    
//                                    if let signedEvent = try? la.account.signEvent(nEvent) {
//                                        //                        print(signedEvent.wrappedEventJson())
//                                        Unpublisher.shared.publishNow(signedEvent)
//                                        //                        noteCancellationId = up.publish(signedEvent)
//                                        text = ""
//                                    }
//                                }
//                            }
//                            else if rootDM != nil {
//                                Divider()
//                                Button(String(localized:"Accept message request", comment:"Button to accept a Direct Message request")) {
//                                    conv.accepted = true
//                                    conv.dmState.accepted = true
//                                    conv.dmState.didUpdate.send()
//                                    DataProvider.shared().saveToDiskNow(.viewContext)
//                                    DirectMessageViewModel.default.reloadAccepted()
//                                    
//                                }
//                                .buttonStyle(NRButtonStyle(style: .borderedProminent))
//                            }
//                        }
//                        .padding(.vertical, 5)
//                        .background(theme.listBackground)
//                    }
                }
                .onAppear {
                    guard !didLoad else { return }
                    didLoad = true
                    guard let lastDay = messagesByDay.keys.sorted(by: { $0 < $1 }).last else { return }
                    guard (messagesByDay[lastDay]?.sorted(by: { $0.created_at < $1.created_at }).last) != nil else { return }
                }
                .onAppear {
                    if (contact == nil) {
                        if let contactPubkey {
                            req(RM.getUserMetadata(pubkey: contactPubkey))
                        }
                    }
                }
                .toolbarNavigationBackgroundVisible()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("\(contact?.authorName ?? String(localized:"DM", comment:"Navigation title for a DM conversation screen (Direct Message)"))")
                            .onTapGesture {
                                withAnimation {
                                    proxy.scrollTo(top)
                                }
                            }
                    }
                }
                .background(theme.listBackground)
            }
            .nosturNavBgCompat(theme: theme)
            .task {
                // TODO: CHANGE TO REALTIME DM SUBSCRIPTION
                guard let theirPubkey = self.theirPubkey else {
                    L.og.error("🔴🔴 Could not find contact pubkey (theirPubkey)")
                    return
                }
                
                nxReq(
                    Filters(
                        authors: [pubkey],
                        kinds: [4],
                        tagFilter: TagFilter(tag: "p", values: [theirPubkey]),
                        limit: 1000
                    ),
                    subscriptionId: "DM-S"
                )
                
                nxReq(
                    Filters(
                        authors: [theirPubkey],
                        kinds: [4],
                        tagFilter: TagFilter(tag: "p", values: [pubkey]),
                        limit: 1000
                    ),
                    subscriptionId: "DM-R"
                )
            }
            
            
            .withNavigationDestinations()
            .environment(\.containerID, "Messages")
        }
        else {
            Text("Error: could not find contact pubkey", comment: "Error shown on DM conversation screen")
                .centered()
                .nosturNavBgCompat(theme: theme)
        }
    }
}

struct DMConversationView17: View {
    private let participantPs: Set<String>
    private let ourAccountPubkey: String
    
    @StateObject private var vm: ConversionVM
    
    init(participantPs: Set<String>, ourAccountPubkey: String) {
        self.participantPs = participantPs
        self.ourAccountPubkey = ourAccountPubkey
        _vm = StateObject(wrappedValue: ConversionVM(participantPs: participantPs, ourAccountPubkey: ourAccountPubkey))
    }
    
    var body: some View {
        Container {
            switch vm.viewState {
            case .initializing, .loading:
                ProgressView()
            case .ready(let nrChats):
                Text("nrChats here: \(nrChats.count)")
            case .timeout:
                Text("Unable to load conversation")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .task {
            await vm.load()
        }
    }
}

import NavigationBackport

@available(iOS 17.0, *)
#Preview("New DM") {
    PreviewContainer({ pe in
        pe.parseEventJSON([
            ###"{"content": "Heb veel performance problemen met Nostur de laatste dagen, enig idee waar dat aan kan liggen?", "created_at": 1726123083, "id": "72cffcb18b0c2ccc12947e6788160c79cd8b28231c762124dee35068ea1a0a15", "kind": 14, "pubkey": "06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71", "tags": [["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]], "sig": "edad"}"###,
            ###"{"content":"Testing","created_at":1726126083,"id":"72cffcb18b0c2ccc12947e6788160c79cd8b28231c762124dee35068ea1a0a15","kind":14,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","tags":[["p","06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71"]], "sig": "uhh"}"###
        ])
    }) {
        NBNavigationStack {
            let participantPs: Set<String> = ["06639a386c9c1014217622ccbcf40908c4f1a0c33e23f8d6d68f4abf655f8f71","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"]
            let ourAccountPubkey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
            
            DMConversationView17(participantPs: participantPs, ourAccountPubkey: ourAccountPubkey)
        }
    }
}

#Preview("Old DM") {
    PreviewContainer({ pe in
        pe.loadDMs()
        DirectMessageViewModel.default.load()
    }) {
        NBNavigationStack {
            let preston = "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204"
            let recentDM = PreviewFetcher.fetchEvent("96500cec51f30a7bee4bf15984f574550064913ec8d00e164e9efad34a989236")
            if let recent = recentDM {
                let conv = Conversation(contactPubkey: "85080d3bad70ccdcd7f74c29a44f55bb85cbcd3dd0cbb957da1d215bdb931204", mostRecentMessage: "what", mostRecentDate: .now, mostRecentEvent: recent, unread: 3, dmState: CloudDMState(context: context()), accepted: true)
                DMConversationView(recentDM: recent, pubkey: preston, conv: conv)
            }
        }
    }
}


// INFO
// CloudDMState
// OLD DMS (1 on 1): accountPubkey_: A and contactPubkey_: B
// NEW DMS (2 or more): accountPubkey_: nil, and contactPubkey: concat(A,B,C) (sorted)
import CoreData

class ConversionVM: ObservableObject {
    private var participantPs: Set<String>
    private var ourAccountPubkey: String
    
    @Published var viewState: ConversionVMViewState = .initializing
    
    // bg
    private var cloudDMState: CloudDMState? = nil
    
    init(participantPs: Set<String>, ourAccountPubkey: String) {
        self.participantPs = participantPs
        self.ourAccountPubkey = ourAccountPubkey
    }
    
    private var didLoad = false
    
    @MainActor
    public func load(force: Bool = false) async {
        guard force || !didLoad else { return }
        self.didLoad = true
        self.cloudDMState = await getGroupState()
        
        if let cloudDMState {
            let visibleMessages = await getMessages(cloudDMState)
            viewState = .ready(visibleMessages)
        }
        
        self.fetchDMrelays()
    }
    
    @MainActor
    public func reload(participantPs: Set<String>, ourAccountPubkey: String) async {
        self.participantPs = participantPs
        self.ourAccountPubkey = ourAccountPubkey
        await self.load(force: true)
    }

    
    private func getGroupState() async -> CloudDMState {
        // Get existing or create new
        let participantPs = self.participantPs
        return await withBgContext { bgContext in
            if let groupDMState = CloudDMState.fetchGroup(pubkeys: participantPs, context: bgContext) {
                return groupDMState
            }
            return CloudDMState.create(pubkeys: participantPs, context: bgContext)
        }
    }
    
    private func getMessages(_ cloudDMState: CloudDMState) async -> [NRChatRow] {

        let dmEvents = await withBgContext { bgContext in
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.predicate = NSPredicate(format: "groupId = %@ AND kind IN {4,14}", cloudDMState.conversationId)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            return (try? bgContext.fetch(request)) ?? []
        }
        

        return []
    }
    
    private func sendMessage(_ message: String, ourkeys: Keys) {
        let recipientPubkeys = participantPs.subtracting([ourAccountPubkey])
        let content = message
        var messageEvent =  NostrEssentials.Event(
            pubkey: ourAccountPubkey,
            content: content,
            kind: 14,
            created_at: Int(Date().timeIntervalSince1970),
            tags: []
        )

        // Wrap and send to receiver DM relays, also our own. (we can't unwrap sent, only received to our pubkey)
        for receiverPubkey in participantPs {
            // wrap message
            messageEvent.tags = recipientPubkeys.map { Tag(["p", $0]) }
            do {
                let giftWrap = try createGiftWrap(messageEvent, receiverPubkey: receiverPubkey, keys: ourkeys)
                sendToDMRelay(giftWrap)
            }
            catch {
                
            }
        }
    }
    
    private func sendToDMRelay(_ wrappedEvent: NostrEssentials.Event) {
        
    }
    
    private func fetchDMrelays() {
        let reqFilters = Filters(
            authors: participantPs,
            kinds: [10050],
            limit: 200
        )
        nxReq(
            reqFilters,
            subscriptionId: "DM-" + UUID().uuidString.prefix(48),
            relayType: .READ
        )
        nxReq(
            reqFilters,
            subscriptionId: "DM-" + UUID().uuidString.prefix(48),
            relayType: .SEARCH
        )
    }
}

enum ConversionVMViewState {
    case initializing
    case loading
    case ready([NRChatRow])
    case timeout
    case error(String)
}

func fetchDMrelays(for pubkeys: Set<String>) {
    
}

func getDMrelay(for pubkey: String) {
    
}
