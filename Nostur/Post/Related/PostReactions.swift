//
//  PostReactions.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/07/2024.
//

import SwiftUI
import CoreData
import NavigationBackport

struct PostReactions: View {
    public var eventId: String
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @StateObject private var model = PostReactionsModel()

    @State private var backlog = Backlog(backlogDebugName: "PostReactions")
    @Namespace private var top
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ScrollViewReader { proxy in
            ZStack {
                theme.listBackground // list background
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    LazyVStack(spacing: GUTTER) {
                        if model.reactions.isEmpty {
                            if model.isLoading {
                                ProgressView("Loading reactions…").padding()
                            } else if !model.foundSpam {
                                VStack(spacing: 12) {
                                    if model.fetchTimedOut {
                                        Text("Reactions could not finish loading. Try again.").foregroundStyle(.secondary)
                                    } else {
                                        Text("No reactions found on the available relays.").foregroundStyle(.secondary)
                                    }
                                    Button("Retry") { fetchNewer() }
                                }.padding()
                            }
                        }
                        ForEach(model.reactions) { nrPost in
                            HStack(alignment: .top) {
                                ObservedPFP(nrContact: nrPost.contact)
                                    .onTapGesture {
                                        navigateTo(ContactPath(key: nrPost.pubkey), context: containerID)
                                    }
                                VStack(alignment: .leading) {
                                    NRPostHeaderContainer(nrPost: nrPost)
                                    NIP30ReactionContentView(content: nrPost.content, fastTags: nrPost.fastTags)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(10)
                            .background(theme.listBackground) // each row
                            .overlay(alignment: .bottom) {
                                theme.background.frame(height: GUTTER)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateTo(ContactPath(key: nrPost.pubkey), context: containerID)
                            }
                            .id(nrPost.id)
                            .onAppear {
                                if nrPost.contact.metadata_created_at == 0 {
                                    QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                                }
                            }
                        }
                    }
                    if model.foundSpam && !model.includeSpam {
                        Button {
                            model.includeSpam = true
                            model.load(limit: 500, includeSpam: model.includeSpam)
                                
                        } label: {
                           Text("Show \(model.hiddenReactionCount) reactions outside your Web of Trust")
                                .padding(10)
                                .contentShape(Rectangle())
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Reactions", comment: "Title of list of reactions screen"))
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.listBackground) // screen / toolbar
        .onAppear {
            model.setup(eventId: eventId)
            model.load(limit: 500)
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
#if DEBUG
        L.og.debug("🥎🥎 fetchNewer() (POST REACTIONS)")
#endif
        model.beginFetch()
        let fetchNewerTask = ReqTask(
            reqCommand: { taskId in
                req(PostReactionsModel.historyRequest(eventId: eventId, subscriptionId: taskId))
            },
            processResponseCommand: { (taskId, _, _) in
                Task { @MainActor in model.load(limit: 500, includeSpam: model.includeSpam, finishesFetch: true) }
            },
            timeoutCommand: { taskId in
                model.markFetchTimedOut()
                model.load(limit: 500, includeSpam: model.includeSpam)
            }, timeoutDelivery: .main)
        
        backlog.add(fetchNewerTask)
        fetchNewerTask.fetch()
    }
}
