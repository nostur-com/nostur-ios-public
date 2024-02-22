//
//  ProfileZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/05/2023.
//

import SwiftUI
import CoreData


// How to deal with zaps overview? (High volume accounts vs normal users)
// Get all zaps from last week (.since filter)
// If low, get last month (.since)
// If low, get all...?

// Steps: fetch zaps from relay that have our serializedP
// foreach, fetch zappedEventId if we dont have it

// Posts on user profile screen
@available(iOS 16.0, *)
struct ProfileZaps: View {
    @EnvironmentObject private var themes:Themes
    let er:ExchangeRateModel = .shared
    
    let pubkey:String
    @ObservedObject var contact:Contact
    @ObservedObject var settings:SettingsStore = .shared
    @State var backlog = Backlog(timeout: 8)
    @State var didLoad = false
    @State var nrPosts = ArraySlice<NRPost>()
    @State var zaps = ArraySlice<Event>()
    
    @State var verifiedZapsCount = 0
    @State var verifiedZapsSum = 0.0
    @State var verifiedZapsFiat = "0"
    
    
    var body: some View {
        if !nrPosts.isEmpty {
            Grid {
                GridRow {
                    Text("Zaps received recently", comment: "Heading")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                        .gridCellColumns(2)
                        .padding(.top, 10)
                }
                Divider()
                GridRow {
                    Text("Zaps", comment: "Heading")
                    Text("Sats", comment: "Heading (short for Satoshis)")
                }
                .font(.system(size: 20))
                Group {
                    GridRow {
                        Text(verifiedZapsCount.description)
                            .foregroundColor(.green)
                            .padding(5)
                        Text(verbatim:"\(verifiedZapsSum.clean)")
                            .foregroundColor(.green)
                            .padding(5)
                    }
                    GridRow {
                        Text(verbatim:"")
                        Text(verbatim:"\(verifiedZapsFiat)")
                            .foregroundColor(.green).opacity(0.4)
                    }
                }
                .font(.system(size: 30))
                .fontWeight(.bold)
            }
            
            Divider()
            
            Text("Most received recently on", comment: "Heading above posts which received the most zaps")
                .foregroundColor(.gray)
                .font(.system(size: 20))
        }
        ForEach(nrPosts) { nrPost in
            Box(nrPost: nrPost) {
                PostRowDeletable(nrPost: nrPost, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
            }
            .id(nrPost.id)
            .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
//                    .fixedSize(horizontal: false, vertical: true)
        }
        if nrPosts.isEmpty {
            ProgressView()
        }
        
        Color.clear
            .task { [weak backlog] in
                guard let backlog else { return }
                guard !didLoad else { return }
                didLoad = true
                loadZaps()
                
                let calendar = Calendar.current
                let ago = calendar.date(byAdding: .day, value: -14, to: Date())!
                
                let fetchNewerTask = ReqTask(
                    reqCommand: { (taskId) in
                        req(RM.getAuthorZaps(pubkey: pubkey, since: NTimestamp(date: ago), subscriptionId: taskId))
                    },
                    processResponseCommand: { (taskId, _, _) in
                        self.loadZaps()
                    },
                    timeoutCommand: { [weak backlog] (taskId) in
                        guard let backlog else { return }
                        backlog.timeout = 4
                        try60days()
                    }
                )
                
                backlog.add(fetchNewerTask)
                fetchNewerTask.fetch()
            }
            .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { subscriptionIds in
                bg().perform {
                    let reqTasks = backlog.tasks(with: subscriptionIds)
                    reqTasks.forEach { task in
                        task.process()
                    }
                }
            }
    }
    
    func try60days() {
        let calendar = Calendar.current
        let ago = calendar.date(byAdding: .day, value: -60, to: Date())!
        
        let fetchTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getAuthorZaps(pubkey: pubkey, since: NTimestamp(date: ago), subscriptionId: taskId))
            },
            processResponseCommand: { (taskId, _, _) in
                self.loadZaps()
            },
            timeoutCommand: { (taskId) in
                try180days()
            }
        )
        backlog.add(fetchTask)
        fetchTask.fetch()
    }
    
    func try180days() {
        let calendar = Calendar.current
        let ago = calendar.date(byAdding: .day, value: -180, to: Date())!
        
        let fetchTask = ReqTask(
            reqCommand: { (taskId) in
                req(RM.getAuthorZaps(pubkey: pubkey, since: NTimestamp(date: ago), subscriptionId: taskId))
            },
            processResponseCommand: { (taskId, _, _) in
                self.loadZaps()
            },
            timeoutCommand: { (taskId) in
                L.og.info("No zaps to be found, checked 14, 60, 180 days ago.")
            }
        )
        
        backlog.add(fetchTask)
        fetchTask.fetch()
    }
    
    func loadZaps() {
        let ctx = bg()
        let zapperPubkey = contact.zapperPubkey ?? "WHAT"
        ctx.perform {
            let calendar = Calendar.current
            let ago = calendar.date(byAdding: .day, value: -14, to: Date())!
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format:
                                        "created_at > %i AND kind = 9735 AND tagsSerialized CONTAINS %@",
                                       ago.timeIntervalSince1970,
                                       serializedP(pubkey)) // OPTIMIZATION HACK
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            if let zaps = try? ctx.fetch(fr) {
                
                let verifiedZaps = zaps.filter { zap in
                    zap.pubkey == zapperPubkey
                }
                
                let verifiedZapsCount = verifiedZaps.count
                
                let verifiedZapsSum = verifiedZaps.reduce(0) { partialResult, zap in
                    return partialResult + zap.naiveSats
                }
                
                let verifiedZapsFiat = String(format: "($%.02f)",(Double(verifiedZapsSum / 100000000 * er.bitcoinPrice)))
                
                let nrPosts = zaps
                    .uniqued(on: { $0.zappedEventId })
                    .compactMap { $0.zappedEvent }
                    .map { NRPost(event: $0) }
                    .sorted(by: { $0.footerAttributes.zapTally > $1.footerAttributes.zapTally })
                    .prefix(25)
                
                DispatchQueue.main.async {
                    self.nrPosts = nrPosts
                    self.verifiedZapsCount = verifiedZapsCount
                    self.verifiedZapsSum = verifiedZapsSum
                    self.verifiedZapsFiat = verifiedZapsFiat
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct ProfileZaps_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        PreviewContainer({ pe in
            // TODO: FIX THESE
            pe.loadContacts()
            pe.loadZaps()
        }) {
            ScrollView {
                let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
                let contact = PreviewFetcher.fetchContact(pubkey)
                
                if let contact {
                    ProfileZaps(pubkey:pubkey, contact:contact)
                }
            }
        }
    }
}

