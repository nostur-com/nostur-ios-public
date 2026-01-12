//
//  PostZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/07/2024.
//

import SwiftUI
import CoreData
import NavigationBackport
import Combine

struct PostZaps: View {
    public let nrPost: NRPost
    @Environment(\.theme) private var theme
    @StateObject private var model = PostZapsModel()

    @State private var backlog = Backlog(backlogDebugName: "PostZaps")
    @Namespace private var top
    
    @StateObject private var reverifier = ZapperPubkeyVerifier()
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ScrollViewReader { proxy in
            ZStack {
                theme.listBackground
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    LazyVStack(spacing: GUTTER) {
                        ForEach(model.verifiedZaps) { nrPost in
                            Box {
                                NxZapReceipt(fromPubkey: nrPost.fromPubkey!, nrPost: nrPost)
                            }
                        }
                        
                        if !model.unverifiedZaps.isEmpty {
                            Text("Unverified zaps", comment: "List of unverified zaps")
                                .fontWeight(.bold)
                                .padding(10)
                            Text("This can be caused by the receiver switching to a different lightning address")
                                .font(.caption)
                                .italic()
                                .padding(10)
                            
                            switch reverifier.state {
                            case .idle:
                                Button("Verify again") {
                                    reverifier.run(nrPost.pubkey)
                                }
                            case .loading:
                                HStack {
                                    ProgressView()
                                    Text("Verifying...")
                                }
                            case .noKind0:
                                Text("Could not find latest user profile (kind-0)")
                            case .noLud:
                                Text("User does not have a lightning address set")
                            case .noZapperPubkey:
                                Text("Users wallet does not support nostr")
                            case .done:
                                Text("Verifying... Done.")
                            }
                            
                            ForEach(model.unverifiedZaps) { nrPost in
                                Box {
                                    NxZapReceipt(fromPubkey: nrPost.fromPubkey!, nrPost: nrPost)
                                }
                            }
                        }
                        
                        if model.foundSpam && !model.includeSpam {
                            Button {
                                model.includeSpam = true
                                model.load(limit: 500, includeSpam: model.includeSpam)
                                    
                            } label: {
                               Text("Show more")
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .background(theme.listBackground)
        .navigationTitle(String(localized: "Zaps", comment: "Title of list of zaps screen"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.setup(eventId: nrPost.id)
            model.load(limit: 500)
            fetchNewer()
        }
        .onChange(of: reverifier.state) { newState in
            if newState == .done {
                model.load(limit: 500, includeSpam: model.includeSpam)
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
    }
    
    private func fetchNewer() {
#if DEBUG
        L.og.debug("🥎🥎 fetchNewer() (POST ZAPS)")
#endif
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getEventReferences(
                        ids: [nrPost.id],
                        limit: 500,
                        subscriptionId: taskId,
                        kinds: [9735],
                        since: NTimestamp(timestamp: Int(model.mostRecentZapCreatedAt))
                    ))
                }
            },
            processResponseCommand: { (taskId, _, _) in
                model.load(limit: 500, includeSpam: model.includeSpam)
            },
            timeoutCommand: { taskId in
                model.load(limit: 500, includeSpam: model.includeSpam)
            })
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
}

struct NxZapReceipt: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
        
    public var fromPubkey: String
    public let nrPost: NRPost

    @ObservedObject private var nrContact: NRContact
    
    init(fromPubkey: String, nrPost: NRPost) {
        self.fromPubkey = fromPubkey
        self.nrPost = nrPost
        
        self.nrContact = NRContact.instance(of: fromPubkey)
    }
    
    var body: some View { // Copy pasta from Kind1Default, remove all non 9735 stuff, removed footer, removed thread connecting lines
        HStack(alignment: .top) {
            VStack(alignment: .center) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(theme.accent)
                Text(nrPost.sats, format: .number.notation((.compactName)))
                    .font(.title3)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(nrPost.sats) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(nrPost.sats != 0 ? 0.5 : 0)
                }
            }
            .frame(width: 70)
            
            InnerPFP(pubkey: fromPubkey, pictureUrl: nrContact.pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER, color: nrContact.randomColor)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .onTapGesture {
                    navigateTo(nrContact, context: containerID)
                }
            
            VStack(alignment: .leading, spacing: 3) { // Post container
                ZappedFromName(pubkey: fromPubkey, nrPost: nrPost)
                
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: false, fullWidth: false)
                    .environment(\.availableWidth, DIMENSIONS.articleRowImageWidth(availableWidth) - 80)
                    .frame(maxWidth: DIMENSIONS.articleRowImageWidth(availableWidth) - 80, minHeight: 40, alignment: .leading)
            }
            .task {
                QueuedFetcher.shared.enqueue(pTag: fromPubkey)
            }
        }
    }
}


import NostrEssentials

class ZapperPubkeyVerifier: ObservableObject {
    @Published public var state: ZPVState = .idle
    
    private var backlog = Backlog(timeout: 10.0, auto: true, backlogDebugName: "ZapperPubkeyVerifier")
    
    @MainActor
    public func run(_ pubkey: String) {
        Task {
            guard let kind0 = await getLatestKind0(pubkey: pubkey) else {
                self.state = .noKind0
                return
            }
            
            guard let anyLud = getLatestLud(kind0: kind0) else {
                self.state = .noLud
                return
            }
            
            
            guard (await getZapperPubkey(anyLud: anyLud)) != nil else {
                self.state = .noZapperPubkey
                return
            }
            
            self.state = .done
        }
    }
    
    // task 1: get latest kind 0
    private func getLatestKind0(pubkey: String) async -> NEvent? {
        await withCheckedContinuation { continuation in
            let task = ReqTask(
                debounceTime: 3.0,
                subscriptionId: "KIND-0-",
                reqCommand: { taskId in
                    outboxReq(
                        NostrEssentials.ClientMessage(
                            type: .REQ,
                            subscriptionId: taskId,
                            filters: [
                                Filters(
                                    authors: [pubkey],
                                    kinds: [0],
                                    limit: 1
                                )
                            ]
                        ),
                        relayType: .READ
                    )
                },
                processResponseCommand: { [weak self] taskId, relayMessage, event in
                    guard let self else { continuation.resume(returning: nil); return  }
                    self.backlog.clear()
                    bg().perform {
                        let fr = Event.fetchRequest()
                        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                        fr.predicate = NSPredicate(format: "kind == 0 AND pubkey == %@", pubkey)
                        if let kind0 = try? bg().fetch(fr).first {
                            continuation.resume(returning: kind0.toNEvent())
                        }
                        else {
                            continuation.resume(returning: nil)
                        }
                    }
                },
                timeoutCommand: { [weak self] taskId in
                    guard let self else { continuation.resume(returning: nil); return }
                    self.backlog.clear()
#if DEBUG
                    L.og.debug("ZapperPubkeyVerifier.getLatestKind0(): timeout -[LOG]-")
#endif
                    bg().perform {
                        let fr = Event.fetchRequest()
                        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                        fr.predicate = NSPredicate(format: "kind == 0 AND pubkey == %@", pubkey)
                        if let kind0 = try? bg().fetch(fr).first {
                            continuation.resume(returning: kind0.toNEvent())
                        }
                        else {
                            continuation.resume(returning: nil)
                        }
                    }
                })
            backlog.add(task)
            task.fetch()
        }
    }
    
    // task 2: get latest .anyLud
    private func getLatestLud(kind0: NEvent) -> String? {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: kind0.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return nil
        }
        
       return metaData.anyLud
    }
    
    // task 3: get zapperpubkey
    private func getZapperPubkey(anyLud: String) async -> String? {
        do {
            let response = if anyLud.contains("@") {
                try await LUD16.getCallbackUrl(lud16: anyLud)
            }
            else {
                try await LUD16.getCallbackUrl(lud06: anyLud)
            }
            guard let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey)
            else {
                return nil
            }
            
            return zapperPubkey
        }
        catch {
            L.og.error("⚡️🔴 problem in lnurlp \(error)")
            return nil
        }
    }
}


enum ZPVState {
    case idle
    case loading
    case noKind0
    case noLud
    case noZapperPubkey
    case done
}


extension NSetMetadata {
    public var anyLud: String? {
        if let lud16, lud16 != "" {
            return lud16
        }
        else if let lud06, lud06 != "" {
            return lud06
        }
        return nil
    }
}
