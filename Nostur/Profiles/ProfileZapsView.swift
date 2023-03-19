//
//  ProfileZapsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

// NOTES ON USER PROFILE SCREEN
struct ProfileZapsView: View {
    
    @EnvironmentObject var er:ExchangeRateModel
    var sp:SocketPool = .shared
    var contact:Contact?
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var zaps: FetchedResults<Event> // ZAP EVENTS FROM CUSTODIAL PROVIDER
    var zaps_:[Event] { Array(zaps) } // For onChange()
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.zapTally, order: .reverse)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var posts: FetchedResults<Event> // AUTHORS POSTS
    
    var vPosts:[VPost] {
        posts.map(VPostTransformer.shared.toVPost)
    }
    
    init(pubkey:String, contact:Contact? = nil) {
        if (contact != nil) {
            self.contact = contact
            _zaps = FetchRequest(
                sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
                predicate: NSPredicate(format: "kind = 9735 AND tagsSerialized CONTAINS %@", serializedP(contact!.pubkey)) // OPTIMIZATION HACK
            )
            
            _posts = FetchRequest(
                sortDescriptors: [SortDescriptor(\Event.zapTally, order: .reverse)],
                predicate: NSPredicate(format: "kind = 1 AND zapTally > 0 AND pubkey == %@", contact!.pubkey)
            )
        }
    }
    
    var pubkey:String { contact!.pubkey }
    
    // TODO: WHAT IF ZAPPER PUBKEY CHANGED. OLD VERIFIED ZAPS HUHH??!! KEEP TRACK
    var verifiedZaps:[Event] {
        zaps.filter { zap in
            zap.pubkey == (contact?.zapperPubkey ?? "WHAT")
        }
    }
    
    var sumSats:Double {
        verifiedZaps.reduce(0) { partialResult, zap in
            return partialResult + zap.naiveSats
        }
    }
    
    var fiatPrice:String {
        get {
            String(format: "($%.02f)",(Double(sumSats / 100000000 * er.bitcoinPrice)))
        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        if contact != nil {
            Group {
                if (zaps.count == 0) {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(50)
                        Spacer()
                    }
                }
                else {
                    VStack {
                        Grid {
                            GridRow {
                                Text("RECEIVED TOTALS")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                                    .gridCellColumns(2)
                            }
                            Divider()
                            GridRow {
                                Text("ZAPS")
                                Text("SATS")
                            }
                            .font(.system(size: 20))
                            Group {
                                GridRow {
                                    Text(verifiedZaps.count.description)
                                        .foregroundColor(.green)
                                        .padding(5)
                                    Text("\(sumSats.clean)")
                                        .foregroundColor(.green)
                                        .padding(5)
                                }
                                GridRow {
                                    Text("")
                                    Text("\(fiatPrice)")
                                        .foregroundColor(.green).opacity(0.4)
                                }
                            }
                            .font(.system(size: 30))
                            .fontWeight(.bold)
                        }
                        
                        Divider()
                        
                        VStack {
                            Text("MOST RECEIVED ON:")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                            
                            LazyVStack {
                                ForEach(vPosts.filter { $0.event.zapTally > 0  } .prefix(10)) { vPost in
                                    NoteRow(vPost: vPost)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                print("🟢 ProfileZapsView.onAppear always REQ.9735 \(pubkey)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorZaps(pubkey: pubkey)))
            }
            .onChange(of: zaps_) { newZapEvents in
                var missingContacts:[String] = []
                var missingEvents:[String] = []
                
                for event in newZapEvents {
                    if (event.zapFromRequest == nil) { print("🔴🔴 wheres the zap request bro. event.id: \(event.id)");continue }
                    if (event.zapFromRequest?.contact == nil || event.zapFromRequest?.contact?.metadata_created_at == 0) {
                        missingContacts.append(event.zapFromRequest!.pubkey)
                    }
                    if (event.zappedEventId != nil && event.zappedEvent == nil) {
                        if (event.zapFromRequest?.zappedEvent == nil) {
                            missingEvents.append(event.zappedEventId!)
                        }
                    }
                }
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingContacts)))
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvents(ids: missingEvents)))
                if (missingContacts.count > 0  || missingEvents.count > 0) {
                    print("🟣 Fetching \(missingContacts.count) missing contacts, and \(missingEvents.count ) missing events that received zaps")
                }
            }
        }
    }
}

struct ProfileZapsView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        
        let contact = PreviewFetcher.fetchContact(pubkey)
        
        if (contact != nil) {
            ScrollView {
                ProfileZapsView(pubkey:pubkey, contact: contact)
                    .withPreviewEnvironment()
            }
        }
    }
}

