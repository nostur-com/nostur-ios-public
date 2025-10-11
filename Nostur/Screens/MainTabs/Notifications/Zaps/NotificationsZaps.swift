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

struct NotificationsZaps: View {
    private let pubkey: String
    @Environment(\.theme) private var theme
    @ObservedObject private var settings: SettingsStore = .shared
    @StateObject private var model = ZapsFeedModel()
    @State private var backlog = Backlog(backlogDebugName: "NotificationsZaps")
    @Binding private var navPath: NBNavigationPath
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Zaps" }
        set { setSelectedNotificationsTab(newValue) }
    }
    
    @FetchRequest
    private var pNotifications:FetchedResults<PersistentNotification>
    
    init(pubkey: String, navPath: Binding<NBNavigationPath>) {
        self.pubkey = pubkey
        _navPath = navPath
        let fr = PersistentNotification.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND type_ IN %@ AND NOT id == nil", pubkey, [PNType.failedZap.rawValue,PNType.failedZaps.rawValue,PNType.failedZapsTimeout.rawValue,PNType.failedLightningInvoice.rawValue])
        _pNotifications = FetchRequest(fetchRequest: fr)
    }
    
    private var notifications: [ZapOrNotification] {
        // combine Post/Profile zaps and PersistentNotifications in the list
        return (pNotifications.map { pNot in
            ZapOrNotification(id: "NOTIF-" + pNot.id.uuidString, type: .NOTIFICATION, notification: pNot)
        } + model.postOrProfileZaps.map({ postOrProfileZaps in
            ZapOrNotification(id: postOrProfileZaps.id, type: .ZAP, postOrProfileZaps: postOrProfileZaps)
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(notifications) { pNotification in
                        switch pNotification.type {
                        case .NOTIFICATION:
                            ZapNotificationView(notification: pNotification.notification!)
                                .padding(10)
                                .background(theme.listBackground)
                                .overlay(alignment: .bottom) {
                                    theme.background.frame(height: GUTTER)
                                }
                                .id(pNotification.id)
                        case .ZAP:
                            VStack {
                                if let postOrProfileZaps = pNotification.postOrProfileZaps {
                                    if postOrProfileZaps.type == .Post, let postZaps = postOrProfileZaps.post {
                                        PostZapsView(postZaps: postZaps)
                                    }
                                    else if postOrProfileZaps.type == .Profile, let profileZap = postOrProfileZaps.profile {
                                        ProfileZap(zap: profileZap)
                                    }
                                }
                            }
                            .padding(10)
                            .background(theme.listBackground)
                            .overlay(alignment: .bottom) {
                                theme.background.frame(height: GUTTER)
                            }
                            .id(pNotification.id)
                        }
                    }
                    VStack {
                        if !model.postOrProfileZaps.isEmpty {
                            Button("Show more") {
                                model.showMore()
                            }
                            .padding(.bottom, 40)
                            .buttonStyle(.bordered)
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
                if navPath.count == 0, let topId = notifications.first?.id {
                    withAnimation {
                        proxy.scrollTo(topId)
                    }
                }
            }
        }
        .background(theme.listBackground)
        .onAppear {
            model.setup(pubkey: pubkey)
            model.load(limit: 150)
            fetchNewer()
        }
        .onChange(of: pubkey) { newPubkey in
            model.setup(pubkey: newPubkey)
            model.load(limit: 150)
            fetchNewer()
        }
        .onReceive(receiveNotification(.newZaps)) { _ in
            // Receive here for logged in account (from NotificationsViewModel). In multi-column we don't track .newReactions for other accounts (unread badge)
            model.load(limit: 150) { mostRecentCreatedAt in
                saveLastSeenZapCreatedAt(mostCreatedAt: mostRecentCreatedAt)
            }
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
            bg().perform {
                guard let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        .onChange(of: settings.webOfTrustLevel) { _ in
            model.setup(pubkey: pubkey)
            model.load(limit: 150)
            fetchNewer()
        }
    }
    
    private func fetchNewer() {
#if DEBUG
        L.og.debug("🥎🥎 fetchNewer() (ZAPS)")
#endif
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [9735],
                        limit: 1000,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(model.mostRecentZapCreatedAt))
                    ))
                }
            },
            processResponseCommand: { (taskId, _, _) in
                model.load(limit: 500)
            },
            timeoutCommand: { taskId in
                model.load(limit: 500)
            })
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
    
    func saveLastSeenZapCreatedAt(mostCreatedAt: Int64) {
        guard selectedTab == "Notifications" && selectedNotificationsTab == "Zaps" else { return }
        guard mostCreatedAt != 0 else { return }
        if let account = account() {
            if account.lastSeenZapCreatedAt < mostCreatedAt {
                account.lastSeenZapCreatedAt = mostCreatedAt
                DataProvider.shared().saveToDiskNow(.viewContext) // Account is from main context
            }
        }
    }
}

struct PostZapsView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var postZaps: GroupedPostZaps
    @ObservedObject private var footerAttributes: FooterAttributes
    
    init(postZaps: GroupedPostZaps) {
        self.postZaps = postZaps
        self.footerAttributes = postZaps.nrPost.footerAttributes
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(theme.accent)
//                Text(Double(footerAttributes.zapTally).satsFormatted)
//                    .font(.title2)
                Text(postZaps.zaps.reduce(0, { $0 + $1.sats }), format: .number.notation((.compactName)))
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
                    ZapsForThisNote(zaps: postZaps.zaps)
                    NoteMinimalContentView(nrPost: postZaps.nrPost, lineLimit: 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(postZaps.nrPost, context: "Default")
        }
    }
}

struct ProfileZap: View {
    public var zap: SingleZap
    @Environment(\.theme) private var theme
    
    var body: some View {
        HStack(alignment: .top) {
            VStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(theme.accent)
                Text(zap.sats, format: .number.notation((.compactName)))
                    .font(.title2)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(zap.sats) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(zap.sats != 0 ? 0.5 : 0)
                }
            }
            .frame(width:80)
            
            VStack(alignment:.leading, spacing: 3) {
                PFP(pubkey: zap.pubkey, pictureUrl: zap.pictureUrl, forceFlat: true)
                Text("**\(zap.authorName ?? "??")** zapped your profile", comment: "Message when someone zapped your profile")
                Text(zap.content)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) {
                Ago(zap.createdAt).layoutPriority(2)
                    .foregroundColor(.gray)
            }
            .onAppear {
                if (zap.authorName == nil) {
                    QueuedFetcher.shared.enqueue(pTag: zap.pubkey)
                }
            }
            .onTapGesture {
                navigateTo(ContactPath(key: zap.pubkey), context: "Default")
            }
        }
    }
}

struct ZapsForThisNote: View {
    public var zaps: [SingleZap]
    
//    private var deduplicated:[String: (String, Contact?, Double, Date, String?)] { // [string: (pubkey, Contact?, amount, created_at)]
//        var d = [String: (String, Contact?, Double, Date, String?)]()
//        // show only 1 zap per pubkey, combine total amount, track most recent created_at
//        zaps
//            .map {
//                ($0.zapFromRequest, $0.date, $0.naiveSats, $0.zapFromRequest?.contact?.authorName)
//            }
//            .filter {
//                $0.0 != nil
//            }
//            .forEach { tuple in
//                guard tuple.0 != nil else { return }
//                let (req, createdAt, sats, authorName) = tuple
//                if d[req!.pubkey] != nil {
//                    // additional entry, add up sats, and only keep most recent date
//                    let current = d[req!.pubkey]!
//                    let mostRecentDate = current.3 > createdAt ? current.3 : createdAt
//                    d[req!.pubkey] = (current.0, current.1, current.2 + sats, mostRecentDate, current.4)
//                }
//                else {
//                    // first entry
//                    d[req!.pubkey] = (req!.pubkey, req!.contact, sats, createdAt, authorName)
//                }
//            }
//        return d.sorted { $0.value.2 > $1.value.2 }
//            .reduce(into: [String: (String, Contact?, Double, Date, String?)]()) { $0[$1.0] = $1.1 }
//
//    }
    
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(zaps.prefix(10).indices, id: \.self) { index in
                    ZStack(alignment:.leading) {
                        PFP(pubkey: zaps[index].pubkey, pictureUrl: zaps[index].pictureUrl, forceFlat: true)
                            .id(zaps[index].id)
                            .zIndex(-Double(index))
                        
                        Text(zaps[index].sats, format: .number.notation((.compactName)))
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
            if (zaps.count > 1) {
                Text("**\(zaps.first(where: { $0.authorName != nil })?.authorName ?? "???")** and \(zaps.count - 1) others zapped your post", comment: "Message when (name) and X others zapped your post")
            }
            else {
                Text("**\(zaps.first(where: { $0.authorName != nil })?.authorName ?? "???")** zapped your post", comment: "Message when (name) zapped your post")
            }
        }
        .frame(maxWidth:.infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let first = zaps.first {
                Ago(first.createdAt).layoutPriority(2)
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
    let id: String
    let type: ZapOrNotificationType
    var postOrProfileZaps: PostOrProfileZaps?
    var notification: PersistentNotification?
    
    var createdAt: Int64 {
        (type == .ZAP ? postOrProfileZaps!.mostRecentCreatedAt : Int64(notification!.createdAt.timeIntervalSince1970))
    }
    
    enum ZapOrNotificationType {
        case ZAP
        case NOTIFICATION
    }
}
