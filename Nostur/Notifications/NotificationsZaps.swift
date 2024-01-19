//
//  NotificationsZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2023.
//

import SwiftUI
import CoreData
import Combine
import NavigationBackport

struct ZapInfo: Identifiable {
    var id:String { zap.id }
    var zap:Event // Main context
    var zappedEventNRPost:NRPost? // Created in BG context
    var zappedEvent:Event? // needed to know if we create should NRPost in bg. because we cannot access zap.zappedEvent, so we set hasZappedEvent in the maincontext, which we can then use in bg.
}

struct NotificationsZaps: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    @StateObject private var fl = FastLoader()
    @State private var didLoad = false
    @State private var backlog = Backlog()
    @Binding private var navPath: NBNavigationPath
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Zaps" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    @State private var zapsForMeDeduplicated = [ZapInfo]()
    @Namespace private var top
    
    @FetchRequest
    private var pNotifications:FetchedResults<PersistentNotification>
    
    private func zapsForNote(_ zap:Event, zapsForMe:[Event]) -> [Event] {
        return zapsForMe.filter { zap in
            if let zappedEventId = zap.zappedEventId {
                return zap.id == zappedEventId
            }
            return false
        }
    }
    
    init(pubkey:String, navPath:Binding<NBNavigationPath>) {
        _navPath = navPath
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND type_ IN %@", pubkey, [PNType.failedZap.rawValue,PNType.failedZaps.rawValue,PNType.failedZapsTimeout.rawValue,PNType.failedLightningInvoice.rawValue])
        _pNotifications = FetchRequest(fetchRequest: fr)
    }
    
    private var notifications:[ZapOrNotification] {
        // combine nrPosts and PersistentNotifications in the list
        return (pNotifications.map { pNot in
            ZapOrNotification(id: "NOTIF-" + pNot.id.uuidString, type: .NOTIFICATION, notification: pNot)
        } + zapsForMeDeduplicated.map({ zapInfo in
            ZapOrNotification(id: zapInfo.id, type: .ZAP, zapInfo: zapInfo)
        }))
        .sorted(by: { p1, p2 in
            p1.createdAt > p2.createdAt
        })
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                LazyVStack(alignment:.leading, spacing: 10) {
                    ForEach(notifications) { pNotification in
                        switch pNotification.type {
                        case .NOTIFICATION:
                            ZapNotificationView(notification: pNotification.notification!)
                                .padding(10)
                                .background(themes.theme.background)
                                .id(pNotification.id)
                        case .ZAP:
                            VStack {
                                if let nrPost = pNotification.zapInfo!.zappedEventNRPost {
                                    PostZap(nrPost: nrPost, zaps:fl.events)
                                }
                                else {
                                    if let zapFrom = pNotification.zapInfo!.zap.zapFromRequest {
                                        ProfileZap(zap: pNotification.zapInfo!.zap, zapFrom:zapFrom)
                                    }
                                }
                            }
                            .padding(10)
                            .background(themes.theme.background)
                            .id(pNotification.id)
                        }
                    }
                    VStack {
                        if !zapsForMeDeduplicated.isEmpty {
                            Button("Show more") {
                                guard let account = account() else { return }
                                fl.predicate = NSPredicate(
                                    format: "otherPubkey == %@" + // ONLY TO ME
                                    "AND kind == 9735 " +
                                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                                    account.publicKey,
                                    NRState.shared.blockedPubkeys)
            //                    fl.offset = (fl.events.count - 1)
                                fl.loadMore(500)
                                if let until = fl.events.last?.created_at {
                                    req(RM.getMentions(
                                        pubkeys: [account.publicKey],
                                        kinds: [9735],
                                        limit: 500,
                                        until: NTimestamp(timestamp: Int(until))
                                    ))
                                }
                                else {
                                    req(RM.getMentions(pubkeys: [account.publicKey], kinds: [9735], limit:500))
                                }
                            }
                            .padding(.bottom, 40)
                            .buttonStyle(.bordered)
    //                        .tint(.accentColor)
                        }
                        else {
                            ProgressView()
                        }
                    }
                    .hCentered()
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedNotificationsTab == "Zaps" else { return }
                guard let tabName = notification.object as? String, tabName == "Notifications" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard !didLoad else { return }
            load()
        }
        .onReceive(receiveNotification(.newZaps)) { [weak fl] _ in
            guard let fl else { return }
            guard let account = account() else { return }
            let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
            fl.onComplete = {
                saveLastSeenZapCreatedAt() // onComplete from local database
            }
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i " +
                    "AND otherPubkey == %@" + // ONLY TO ME
                    "AND kind == 9735 " +
                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                    currentNewestCreatedAt,
                account.publicKey,
                NRState.shared.blockedPubkeys
            )
            fl.loadNewerEvents(5000, taskId:"newZaps")
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak fl, weak backlog] subscriptionIds in
            bg().perform {
                guard let fl, let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { [weak fl, weak backlog] _ in
            guard let fl, let backlog else { return }
            fl.events = []
            backlog.clear()
            load()
        }
        .onChange(of: settings.webOfTrustLevel) { [weak fl] _ in
            guard let fl else { return }
            fl.events = []
            backlog.clear()
            load()
        }
        .simultaneousGesture(
               DragGesture().onChanged({
                   if 0 < $0.translation.height {
                       sendNotification(.scrollingUp)
                   }
                   else if 0 > $0.translation.height {
                       sendNotification(.scrollingDown)
                   }
               }))
    }
    
    @State var subscriptions = Set<AnyCancellable>()
    
    private func load() {
        guard let account = account() else { return }
        didLoad = true
        fl.$events
            .sink(receiveValue: { events in
                let zapsForMeDeduplicated = events
                    .uniqued(on: { $0.zappedEventId }) // Deplicated
                    .filter {
                        // Only for me
                        $0.otherPubkey != nil && $0.otherPubkey == account.publicKey
                    }
                
                let p = zapsForMeDeduplicated.map {
                    ZapInfo(zap: $0, zappedEvent: $0.zappedEvent)
                }
                                
                bg().perform {
                    let transformed = p.map { zapInfo in
                        return ZapInfo(
                            zap: zapInfo.zap,
                            zappedEventNRPost: zapInfo.zappedEvent != nil ? NRPost(event: zapInfo.zappedEvent!.toBG()!): nil,
                            zappedEvent: zapInfo.zappedEvent)
                    }
                    DispatchQueue.main.async {
                        self.zapsForMeDeduplicated = transformed
                        
                        self.saveLastSeenZapCreatedAt()
                    }
                }
            })
            .store(in: &subscriptions)
        
        fl.reset()
        fl.nrPostTransform = false
        fl.predicate = NSPredicate(
            format:
                "otherPubkey == %@ AND kind == 9735 AND NOT zapFromRequest.pubkey IN %@",
            account.publicKey,
            NRState.shared.blockedPubkeys
            )
        fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fl.onComplete = { [weak fl] in
            guard let fl else { return }
            self.saveLastSeenZapCreatedAt()
            self.fetchNewer()
            fl.onComplete = {
                saveLastSeenZapCreatedAt() // onComplete from local database
            }
        }
        fl.loadMore(500)
    }
    
    private func fetchNewer() {
        guard let account = account() else { return }
        let fetchNewerTask = ReqTask(
            reqCommand: { [weak fl] (taskId) in
                guard let fl else { return }
                req(RM.getMentions(
                    pubkeys: [account.publicKey],
                    kinds: [9735],
                    limit: 5000,
                    subscriptionId: taskId,
                    since: NTimestamp(timestamp: Int(fl.events.first?.created_at ?? 0))
                ))
            },
            processResponseCommand: { [weak fl] (taskId, _, _) in
                guard let fl else { return }
                L.og.debug("🟠🟠🟠 processResponseCommand \(taskId)")
                let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
                fl.predicate = NSPredicate(
                    format:
                        "created_at >= %i AND otherPubkey == %@ AND kind == 9735 AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                        currentNewestCreatedAt,
                    account.publicKey,
                    NRState.shared.blockedPubkeys
                  )
                fl.loadNewerEvents(5000, taskId: taskId)
            },
            timeoutCommand: { [weak fl] taskId in
                guard let fl else { return }
                fl.loadNewerEvents(5000, taskId: taskId)
            })

        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    func saveLastSeenZapCreatedAt() {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Zaps" else { return }
        if let first = fl.events.first {
            let firstCreatedAt = first.created_at
            bg().perform {
                if let account = account() {
                    if account.lastSeenZapCreatedAt < firstCreatedAt {
                        account.lastSeenZapCreatedAt = firstCreatedAt
                    }
                }
                bgSave()
            }
        }
    }
}

struct PostZap: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var nrPost:NRPost // TODO: ...
    @ObservedObject private var footerAttributes:FooterAttributes
    private var zaps:[Event]
    
    init(nrPost: NRPost, zaps:[Event]) {
        self.nrPost = nrPost
        self.footerAttributes = nrPost.footerAttributes
        self.zaps = zaps
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(themes.theme.accent)
                Text(Double(footerAttributes.zapTally).satsFormatted)
                    .font(.title2)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(footerAttributes.zapTally) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(footerAttributes.zapTally != 0 ? 0.5 : 0)
                }
            }
            .frame(width:80)
            VStack(alignment:.leading, spacing: 3) {
                Group {
                    ZapsForThisNote(
                        zaps: zaps.filter {
                            $0.zappedEventId == nrPost.id
                        })
                    NoteMinimalContentView(nrPost: nrPost, lineLimit: 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(nrPost)
        }
    }
}

struct ProfileZap: View {
    public var zap:Event
    @ObservedObject public var zapFrom:Event
    @EnvironmentObject private var themes:Themes
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(themes.theme.accent)
                Text(zap.naiveSats.satsFormatted)
                    .font(.title2)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(zap.naiveSats) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(zap.naiveSats != 0 ? 0.5 : 0)
                }
            }
            .frame(width:80)
            VStack(alignment:.leading, spacing: 3) {
                PFP(pubkey: zapFrom.pubkey, contact: zapFrom.contact)
                Text("**\(zapFrom.contact?.authorName ?? "??")** zapped your profile", comment: "Message when someone zapped your profile")
                Text(zapFrom.noteText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                Ago(zap.created_at).layoutPriority(2)
                    .foregroundColor(.gray)
            }
            .onAppear {
                if (zapFrom.contact_ == nil || zapFrom.contact_?.metadata_created_at == 0) {
                    EventRelationsQueue.shared.addAwaitingEvent(zapFrom, debugInfo: "NoteZaps.002")
                    QueuedFetcher.shared.enqueue(pTag: zapFrom.pubkey)
                }
            }
            .onDisappear {
                if (zapFrom.contact_ == nil || zapFrom.contact_?.metadata_created_at == 0) {
                    QueuedFetcher.shared.dequeue(pTag: zapFrom.pubkey)
                }
            }
            .onTapGesture {
                navigateTo(ContactPath(key: zapFrom.pubkey))
            }
        }
    }
}

struct ZapsForThisNote: View {
    public var zaps:[Event]
    
    private var deduplicated:[String: (String, Contact?, Double, Date, String?)] { // [string: (pubkey, Contact?, amount, created_at)]
        var d = [String: (String, Contact?, Double, Date, String?)]()
        // show only 1 zap per pubkey, combine total amount, track most recent created_at
        zaps
            .map {
                ($0.zapFromRequest, $0.date, $0.naiveSats, $0.zapFromRequest?.contact?.authorName)
            }
            .filter {
                $0.0 != nil
            }
            .forEach { tuple in
                guard tuple.0 != nil else { return }
                let (req, createdAt, sats, authorName) = tuple
                if d[req!.pubkey] != nil {
                    // additional entry, add up sats, and only keep most recent date
                    let current = d[req!.pubkey]!
                    let mostRecentDate = current.3 > createdAt ? current.3 : createdAt
                    d[req!.pubkey] = (current.0, current.1, current.2 + sats, mostRecentDate, current.4)
                }
                else {
                    // first entry
                    d[req!.pubkey] = (req!.pubkey, req!.contact, sats, createdAt, authorName)
                }
            }
        return d.sorted { $0.value.2 > $1.value.2 }
            .reduce(into: [String: (String, Contact?, Double, Date, String?)]()) { $0[$1.0] = $1.1 }

    }
    
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(Array(deduplicated.keys.enumerated().prefix(6)), id: \.1) { index, key in
                    ZStack(alignment:.leading) {
                        PFP(pubkey: deduplicated[key]!.0 , contact: deduplicated[key]!.1)
                            .zIndex(-Double(index))
                        
                        Text("\(deduplicated[key]!.2.satsFormatted)")
                            .font(.caption)
                            .padding(3)
                            .foregroundColor(.white)
                            .background(.orange)
                            .cornerRadius(8)
                            .offset(x:5, y:+15)
                            .zIndex(20)
                    }
                    .offset(x:Double(0 + (35*index)))
                }
            }
            if (deduplicated.values.count > 1) {
                Text("**\(deduplicated.values.first(where: { $0.4 != nil })?.4 ?? "???")** and \(deduplicated.values.count - 1) others zapped your post", comment: "Message when (name) and X others zapped your post")
            }
            else {
                Text("**\(deduplicated.values.first(where: { $0.4 != nil })?.4 ?? "???")** zapped your post", comment: "Message when (name) zapped your post")
            }
        }
        .frame(maxWidth:.infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let first = deduplicated.values.first {
                Ago(first.3).layoutPriority(2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct NotificationsZaps_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        PreviewContainer {
            NotificationsZaps(pubkey: pubkey, navPath: .constant(NBNavigationPath()))
        }
    }
}


struct ZapOrNotification: Identifiable {
    let id:String
    let type:ZapOrNotificationType
    var zapInfo:ZapInfo?
    var notification:PersistentNotification?
    
    var createdAt:Date {
        (type == .ZAP ? zapInfo!.zap.date : notification!.createdAt)
    }
    
    enum ZapOrNotificationType {
        case ZAP
        case NOTIFICATION
    }
}
