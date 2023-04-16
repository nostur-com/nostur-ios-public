////
////  NotificationsZaps.swift
////  Nostur
////
////  Created by Fabian Lachman on 25/02/2023.
////
//
import SwiftUI
import CoreData

struct NotificationsZaps: View, Equatable {
    
    static func == (lhs: NotificationsZaps, rhs: NotificationsZaps) -> Bool {
        lhs.pubkey == rhs.pubkey
        && lhs.blockedPubkeys == rhs.blockedPubkeys
    }
    
    let er:ExchangeRateModel = .shared // Not Observed for performance
    let pubkey:String
    let blockedPubkeys:[String]
    let FETCH_LIMIT = 200
    
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest
    var zaps:FetchedResults<Event>
    
    
    var zapsForMe:[Event] {
        zaps.filter {
            $0.zappedContactPubkey != nil && $0.zappedContactPubkey == pubkey
        }
    }
    
    var myNotesZapped:[Event] {
        // TODO: hmm we can already use zap.zappedEvent... instead of fetching by ID again
        let r = Event.fetchRequest()
        let ids = Set(zapsForMe.compactMap { zap in
            return zap.zappedEventId
        })
        r.predicate = NSPredicate(format: "id IN %@", ids)
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        return (try? viewContext.fetch(r).filter { $0.pubkey == self.pubkey }) ?? []
    }
    
    func zapsForNote(_ note:Event) -> [Event] {
        return zapsForMe.filter { zap in
            if let zappedEventId = zap.zappedEventId {
                return note.id == zappedEventId
            }
            return false
        }
    }
    //
    init(pubkey:String, blockedPubkeys:[String], context:NSManagedObjectContext) {
        self.pubkey = pubkey
        self.blockedPubkeys = blockedPubkeys
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(
            format:
                "zappedContactPubkey == %@" + // ONLY TO ME
            "AND kind == 9735 " + // ONLY ZAPS
            "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS
            pubkey,
            blockedPubkeys
        )
        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(
            format:
                "created_at >= %i " +
            "AND zappedContactPubkey == %@" + // ONLY TO ME
            "AND kind == 9735 " +
            "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS) // OPTIMISATION HACK
            oldestCreatedAt,
            pubkey,
            blockedPubkeys
        )
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _zaps = FetchRequest(fetchRequest: r2)
    }
    //
    var body: some View {
        let _ = Self._printChanges()
        List {
            Section {
                ForEach(zapsForMe) { zap in
                    VStack {
                        if let note = zap.zappedEvent {
                            HStack(alignment: .top) {
                                VStack {
                                    Image(systemName: "bolt.fill")
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
                                        .foregroundColor(.green)
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
                                    PFP(pubkey: zap.zapFromRequest?.pubkey ?? "WTF", pictureUrl: zap.zapFromRequest?.contact?.picture)
                                    Text("**\(zap.zapFromRequest?.contact?.authorName ?? "??")** zapped your profile")
                                    Text(zap.zapFromRequest?.noteText ?? "")
                                }
                                .onTapGesture {
                                    guard let pubkey = zap.zapFromRequest?.pubkey else { return }
                                    navigateTo(ContactPath(key: pubkey))
                                }
                            }
                        }
                    }
                    .background(Color.systemBackground)
                    .padding(.vertical, 10)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Fetch older") {
                        fetchOlderZaps()
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    Spacer()
                }
                .padding(.vertical, 10)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .onAppear {
            fetchZaps()
            if let first = zaps.first {
                ns.account?.lastSeenZapCreatedAt = first.created_at
            }
            DataProvider.shared().save()
        }
    }
    
    func fetchZaps() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [pubkey],
                                kinds: [9735],
                                limit: 500,
                                since: NTimestamp(timestamp: Int(zaps.first?.created_at ?? 0)))
                         )
        )
    }
    
    func fetchOlderZaps() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [9735],
                                limit: 500,
                                until: NTimestamp(timestamp: Int(zaps.last?.created_at ?? 0)))
                         )
        )
    }
}
//
struct ZapsForThisNote: View {
    var zaps:[Event]
    @Environment(\.managedObjectContext) var viewContext
    
    var zapsSorted:[Event] { // $0.sats > $0.sats is slow... so cached..
        zaps
            .filter { $0.zapFromRequest != nil }
            .sorted(by: { $0.naiveSats > $1.naiveSats } )
    }
    
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
        return d
    }
    
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack {
                ForEach(Array(deduplicated.keys.enumerated()), id: \.1) { index, key in
                    ZStack {
                        PFP(pubkey: deduplicated[key]!.0 , pictureUrl: deduplicated[key]!.1)
                            .zIndex(-Double(index))
                        
                        Text("\(deduplicated[key]!.2.satsFormatted)")
                            .font(.caption)
                            .padding(3)
                            .foregroundColor(.white)
                            .background(.orange)
                            .cornerRadius(8)
                            .offset(x:-10, y:+15)
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
        NotificationsZaps(pubkey: pubkey, blockedPubkeys:[],  context: EventsProvider.preview.container.viewContext)
            .withPreviewEnvironment()
    }
}
