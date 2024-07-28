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
    public var eventId: String
    @EnvironmentObject private var themes: Themes
    @StateObject private var model = PostZapsModel()

    @State private var backlog = Backlog()
    @Namespace private var top
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                LazyVStack(spacing: 2) {
                    ForEach(model.verifiedZaps) { nxZap in
                        Box {
                            NxZapReceipt(sats: nxZap.sats, receiptPubkey: nxZap.receiptPubkey, fromPubkey: nxZap.fromPubkey, nrZapFrom: nxZap.nrZapFrom)
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
                        
                        ForEach(model.unverifiedZaps) { nxZap in
                            Box {
                                NxZapReceipt(sats: nxZap.sats, receiptPubkey: nxZap.receiptPubkey, fromPubkey: nxZap.fromPubkey, nrZapFrom: nxZap.nrZapFrom)
                            }
                        }
                    }
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            model.setup(eventId: eventId)
            model.load(limit: 50)
            fetchNewer()
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
        L.og.debug("🥎🥎 fetchNewer() (POST ZAPS)")
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                bg().perform {
                    req(RM.getEventReferences(
                        ids: [eventId],
                        limit: 500,
                        subscriptionId: taskId,
                        kinds: [9735],
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
}

struct NxZapReceipt: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    
    public let sats: Double
    public let receiptPubkey: String
    
    public var fromPubkey: String
    public let nrZapFrom: NRPost
    private var color: Color { randomColor(seed: fromPubkey) }

    @State private var name: String?
    @State private var pictureUrl: URL?
    @State private var subscriptions = Set<AnyCancellable>()
    
    @State var showMiniProfile = false
    @State private var didStart = false
    
    var body: some View { // Copy pasta from Kind1Default, remove all non 9735 stuff, removed footer, removed thread connecting lines
        HStack(alignment: .top) {
            VStack(alignment: .center) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(themes.theme.accent)
                Text(sats.satsFormatted)
                    .font(.title3)
                if (ExchangeRateModel.shared.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(sats) / 100000000 * Double(ExchangeRateModel.shared.bitcoinPrice)))

                    Text("\(fiatPrice)")
                        .font(.caption)
                        .opacity(sats != 0 ? 0.5 : 0)
                }
            }
            .frame(width: 80)
            
            InnerPFP(pubkey: fromPubkey, pictureUrl: pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER, color: color)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .onTapGesture {
                    withAnimation { showMiniProfile = true }
                }
                .overlay(alignment: .topLeading) {
                    if (showMiniProfile) {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    sendNotification(.showMiniProfile,
                                                     MiniProfileSheetInfo(
                                                        pubkey: fromPubkey,
                                                        contact: nrZapFrom.contact,
                                                        location: geo.frame(in: .global).origin
                                                     )
                                    )
                                    showMiniProfile = false
                                }
                        }
                          .frame(width: 10)
                          .zIndex(100)
                          .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                          .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                              showMiniProfile = false
                          }
                    }
                }
            
            VStack(alignment: .leading, spacing: 3) { // Post container
                ZappedFrom(pubkey: fromPubkey, name: name, couldBeImposter: 0, createdAt: nrZapFrom.createdAt)
                
                ContentRenderer(nrPost: nrZapFrom, isDetail: false, fullWidth: false, availableWidth: dim.availableNoteRowWidth - 80, theme: themes.theme, didStart: $didStart)
                    .frame(maxWidth: dim.availableNoteRowWidth - 80, minHeight: 40, alignment: .leading)
//                ReceiptFrom(pubkey: receiptPubkey)
            }
            .task {
                Kind0Processor.shared.receive
                    .subscribe(on: DispatchQueue.global())
                    .receive(on: DispatchQueue.global())
                    .filter { $0.pubkey == fromPubkey }
                    .sink { profile in
                        DispatchQueue.main.async {
                            name = profile.name
                            pictureUrl = profile.pictureUrl
                        }
                    }
                    .store(in: &subscriptions)
                
                Kind0Processor.shared.request.send(fromPubkey)
            }
        }
    }
}
