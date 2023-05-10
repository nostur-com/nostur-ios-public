////
////  NotificationsZaps.swift
////  Nostur
////
////  Created by Fabian Lachman on 25/02/2023.
////
//
import SwiftUI
import CoreData

struct NotificationsZaps: View {
        
    let er:ExchangeRateModel = .shared // Not Observed for performance
    let pubkey:String
    let blockedPubkeys:[String]

    @StateObject var fl = FastLoader()
    @State var backlog = Backlog()
    @EnvironmentObject var ns:NosturState
    
    
    var zapsForMe:[Event] {
        fl.events.filter {
            $0.zappedContactPubkey != nil && $0.zappedContactPubkey == pubkey
        }
    }
    
    var zapsForMeDeduplicated:[Event] {
        fl.events.uniqued(on: { $0.zappedEventId })
    }
    
    var myNotesZapped:[Event] {
        // TODO: hmm we can already use zap.zappedEvent... instead of fetching by ID again
        return zapsForMe.compactMap { $0.zappedEvent }
            .uniqued { event in
                event.id
            }
    }
    
    func zapsForNote(_ note:Event) -> [Event] {
        return zapsForMe.filter { zap in
            if let zappedEventId = zap.zappedEventId {
                return note.id == zappedEventId
            }
            return false
        }
    }
    
    init(pubkey:String, blockedPubkeys:[String]) {
        self.pubkey = pubkey
        self.blockedPubkeys = blockedPubkeys
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            LazyVStack(alignment:.leading, spacing: 0) {
                ForEach(zapsForMeDeduplicated) { zap in
                    VStack {
                        if let note = zap.zappedEvent {
                            HStack(alignment: .top) {
                                VStack {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(Color("AccentColor"))
                                    Text(Double(note.zapTally).satsFormatted)
                                        .font(.title2)
                                    if (er.bitcoinPrice != 0.0) {
                                        let fiatPrice = String(format: "$%.02f",(Double(note.zapTally) / 100000000 * Double(er.bitcoinPrice)))
                                        
                                        Text("\(fiatPrice)")
                                            .font(.caption)
                                            .opacity(note.zapTally != 0 ? 0.5 : 0)
                                    }
                                }
                                .frame(width:80)
                                VStack(alignment:.leading, spacing: 3) {
                                    Group {
                                        ZapsForThisNote(zaps:zapsForNote(note))
                                        NoteMinimalContentView(vPost: note.toVPost(plainText: true)!, lineLimit: 3)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateTo(note.toVPost()!)
                            }
                            .id(note.id)
                        }
                        else {
                            HStack(alignment: .top) {
                                VStack {
                                    Image(systemName: "bolt.fill")
                                        .foregroundColor(Color("AccentColor"))
                                    Text(zap.naiveSats.satsFormatted)
                                        .font(.title2)
                                    if (er.bitcoinPrice != 0.0) {
                                        let fiatPrice = String(format: "$%.02f",(Double(zap.naiveSats) / 100000000 * Double(er.bitcoinPrice)))
                                        
                                        Text("\(fiatPrice)")
                                            .font(.caption)
                                            .opacity(zap.naiveSats != 0 ? 0.5 : 0)
                                    }
                                }
                                .frame(width:80)
                                VStack(alignment:.leading, spacing: 3) {
                                    PFP(pubkey: zap.zapFromRequest?.pubkey ?? "WTF", pictureUrl: zap.zapFromRequest?.contact?.picture, isFollowing: ns.followingPublicKeys.contains(zap.zapFromRequest?.pubkey ?? "WTF"))
                                    Text("**\(zap.zapFromRequest?.contact?.authorName ?? "??")** zapped your profile")
                                    Text(zap.zapFromRequest?.noteText ?? "")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Ago(zap.created_at).layoutPriority(2)
                                        .foregroundColor(.gray)
                                }
                                .onTapGesture {
                                    guard let pubkey = zap.zapFromRequest?.pubkey else { return }
                                    navigateTo(ContactPath(key: pubkey))
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.systemBackground)
                    .boxShadow()
                    .padding(10)
                }
                Button("Show more") {
                    fl.predicate = NSPredicate(
                        format:
                            "zappedContactPubkey == %@" + // ONLY TO ME
                            "AND kind == 9735 " +
                            "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                            pubkey,
                            blockedPubkeys)
//                    fl.offset = (fl.events.count - 1)
                    fl.loadMore(500)
                    if let until = fl.events.last?.created_at {
                        req(RM.getMentions(
                            pubkeys: [pubkey],
                            kinds: [9735],
                            limit: 500,
                            until: NTimestamp(timestamp: Int(until))
                        ))
                    }
                    else {
                        req(RM.getMentions(pubkeys: [pubkey], kinds: [9735], limit:500))
                    }
                }
                .padding(.bottom, 40)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .hCentered()
            }
        }
        .background(Color("ListBackground"))
        .onAppear {
            fl.vPostTransform = false
            fl.predicate = NSPredicate(
                format:
                    "zappedContactPubkey == %@" + // ONLY TO ME
                    "AND kind == 9735 " +
                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                    pubkey,
                    blockedPubkeys
                )
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            fl.loadMore(500)
            
            if let first = fl.events.first, let account = ns.account {
                let firstCreatedAt = first.created_at
                DataProvider.shared().bg.perform {
                    if let account = account.toBG() {
                        account.lastSeenZapCreatedAt = firstCreatedAt
                    }
                    DataProvider.shared().bgSave()
                }
                
            }
            
            let fetchNewerTask = ReqTask(
                reqCommand: { (taskId) in
                    req(RM.getMentions(
                        pubkeys: [pubkey],
                        kinds: [9735],
                        limit: 1500,
                        subscriptionId: taskId,
                        since: NTimestamp(timestamp: Int(fl.events.first?.created_at ?? 0))
                    ))
                },
                processResponseCommand: { (taskId) in
//                    print("🟠🟠🟠 processResponseCommand \(taskId)")
                    let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
                    fl.predicate = NSPredicate(
                        format:
                            "created_at >= %i " +
                            "AND zappedContactPubkey == %@" + // ONLY TO ME
                            "AND kind == 9735 " +
                            "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                            currentNewestCreatedAt,
                            pubkey,
                            blockedPubkeys
                      )
                    fl.loadNewerEvents(1500, taskId: taskId)
                })

            fetchNewerTask.fetch()
        }
        .onReceive(receiveNotification(.newZaps)) { _ in
            let currentNewestCreatedAt = fl.events.first?.created_at ?? 0
            fl.predicate = NSPredicate(
                format:
                    "created_at >= %i " +
                    "AND zappedContactPubkey == %@" + // ONLY TO ME
                    "AND kind == 9735 " +
                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS)
                    currentNewestCreatedAt,
                    pubkey,
                    blockedPubkeys
            )
            fl.loadNewerEvents(5000, taskId:"newZaps")
        }
        .onReceive(receiveNotification(.importedMessagesFromSubscriptionIds)) { notification in
            let importedSubIds = notification.object as! ImportedNotification
            
            let reqTasks = backlog.tasks(with: importedSubIds.subscriptionIds)
            
            reqTasks.forEach { task in
                task.process()
            }
        }
    }
}
//
struct ZapsForThisNote: View {
    var zaps:[Event]
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    var deduplicated:[String: (String, String?, Double, Date, String?)] { // [string: (pubkey, picturUrl?, amount, created_at)]
        var d = [String: (String, String?, Double, Date, String?)]()
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
                    d[req!.pubkey] = (req!.pubkey, req!.contact?.picture, sats, createdAt, authorName)
                }
            }
        return d.sorted { $0.value.2 > $1.value.2 }
            .reduce(into: [String: (String, String?, Double, Date, String?)]()) { $0[$1.0] = $1.1 }

    }
    
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack(alignment:.leading) {
                ForEach(Array(deduplicated.keys.enumerated().prefix(6)), id: \.1) { index, key in
                    ZStack(alignment:.leading) {
                        PFP(pubkey: deduplicated[key]!.0 , pictureUrl: deduplicated[key]!.1, isFollowing: ns.followingPublicKeys.contains(deduplicated[key]!.0))
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
                Text("**\(deduplicated.values.first(where: { $0.4 != nil })?.4 ?? "???")** and \(deduplicated.values.count - 1) others zapped your post")
            }
            else {
                Text("**\(deduplicated.values.first(where: { $0.4 != nil })?.4 ?? "???")** zapped your post")
            }
        }
        .frame(maxWidth:.infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let first = deduplicated.values.first {
                Ago(first.3).layoutPriority(2)
                    .foregroundColor(.gray)
            }
        }
        //        .onAppear {
        ////            self.fetchMissingEventContacts(events:Array(withoutDuplicates.prefix(10)))
        //        }
    }
    //
    //    func fetchMissingEventContacts(events:[Event]) {
    //        let pubkeys = pubkeys(events)
    //        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
    //        let missingPubkeys = pubkeys.filter {
    //            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
    //        }
    //        let emptyContactPubkeys = pubkeys
    //            .compactMap { pubkey in
    //                contacts.first(where: { $0.pubkey == pubkey })
    //            }
    //            .filter { $0.updated_at == 0 }
    //            .map { $0.pubkey }
    //
    //        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
    //        print("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
    //        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    //    }
}

struct NotificationsZaps_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        NotificationsZaps(pubkey: pubkey, blockedPubkeys:[])
            .withPreviewEnvironment()
    }
}
