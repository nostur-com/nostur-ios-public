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
    let FETCH_LIMIT = 13250
    let nav:NavigationModel = .shared
    let sp:SocketPool = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
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
    init(pubkey:String, context:NSManagedObjectContext, onAppear: @escaping (Int64) -> ()) {
        self.pubkey = pubkey
        self.onAppear = onAppear
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "kind == 9735 AND tagsSerialized CONTAINS %@", serializedP(pubkey)) // OPTIMISATION HACK
//        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0

        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND kind == 9735 AND tagsSerialized CONTAINS %@", oldestCreatedAt, serializedP(pubkey))
//        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _zaps = FetchRequest(fetchRequest: r2)
    }
//    
    var body: some View {
        let _ = print("🧨🧨🧨🧨🧨 NOTIFICATONSZAPS 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        let _ = Self._printChanges()
        List {
            Section {
                ForEach(myNotesZapped) { note in
                    HStack(alignment: .top) {
                        VStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                            Text(Double(note.zapTally).satsFormatted)
                                .font(.title2)
                            if (er.bitcoinPrice != 0.0) {
                                let fiatPrice = String(format: "$%.02f",(Double(note.zapTally) / 100000000 * Double(er.bitcoinPrice)))
                                
                                Text("\(fiatPrice)")
                                    .font(.caption)
                                    .opacity(note.zapTally != 0 ? 0.5 : 0)
                            }
                        }
                        .frame(width:70)
                        VStack(alignment:.leading, spacing: 3) {
                            Group {
                                ZapsForThisNote(zaps:zapsForNote(note), onAppear: self.onAppear)
                                NoteMinimalContentView(vPost: note.toVPost(), lineLimit: 3)
                            }.onTapGesture {
                                nav.navigateTo(note.toVPost())
                            }
                            Divider()
                        }
                    }
                    .id(note.id)
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
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .onAppear {
            fetchZaps()
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
    var onAppear:(Int64) -> ()
    
    var zapsSorted:[Event] { // $0.sats > $0.sats is slow... so cached..
        zaps
            .filter { $0.zapFromRequest != nil }
            .sorted(by: { $0.naiveSats > $1.naiveSats } )
    }

    var body: some View {
        VStack(alignment:.leading) {
            ZStack {
                ForEach(zapsSorted.prefix(10).indices, id:\.self) { index in
                    ZStack {
                        PFP(pubkey: zapsSorted[index].zapFromRequest!.pubkey, pictureUrl: zapsSorted[index].zapFromRequest!.contact?.picture)
                            .id(zapsSorted[index].id)
                            .onAppear {
                                onAppear(zapsSorted[index].created_at)
                            }
                            .zIndex(-Double(index))
                        
                        Text("\(zapsSorted[index].naiveSats.satsFormatted)")
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
            if (zaps.count > 1) {
                Text("**\(zaps.first(where: { $0.zapFromRequest?.contact?.authorName != nil })?.zapFromRequest?.contact?.username ?? "???")** and \(zaps.count - 1) others zapped to your post")
            }
            else {
                Text("**\(zaps.first(where: { $0.zapFromRequest?.contact?.authorName != nil })?.zapFromRequest?.contact?.username ?? "???")** zapped your post")
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
        NotificationsZaps(pubkey: pubkey, context: EventsProvider.preview.container.viewContext) { _ in
            
        }
            .withPreviewEnvironment()
    }
}
