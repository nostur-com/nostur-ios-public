//
//  TopZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2024.
//

import SwiftUI
import SwiftUIFlow

struct TopZaps: View {
    @Environment(\.theme) private var theme
    public let id: String
    
    @StateObject private var model = PostZapsModel()
    @StateObject private var reverifier = ZapperPubkeyVerifier()
    @State private var backlog = Backlog(backlogDebugName: "TopZaps")
    
    @State var actualSize: CGSize? = nil
    @Namespace private var animation
    @State private var animateUpdate = UUID()
    
    var body: some View {
        Flow(.vertical, alignment: .topLeading) {
            if let actualSize {
                ForEach(model.verifiedZaps.indices, id: \.self) { index in
                    ZapPill(
                        nxZap: model.verifiedZaps[index],
                        index: index,
                        availableWidth: actualSize.width
                    )
                    .id(model.verifiedZaps[index].id)
                    .matchedGeometryEffect(
                        id: model.verifiedZaps[index].id,
                        in: animation
                    )
                }
            }
        }
        .animation(.easeIn, value: animateUpdate)
        .frame(maxHeight: 78, alignment: .topLeading) // Max 3 rows
        .clipped()
        .drawingGroup()
        .readSize { size in
            guard actualSize == nil else { return }
            actualSize = size
        }
        .nosturNavBgCompat(theme: theme)
        .onAppear {
            model.setup(eventId: id)
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
                    req(
                        RM.getEventReferences(
                            ids: [id],
                            limit: 500,
                            subscriptionId: taskId,
                            kinds: [9735],
                            since: NTimestamp(
                                timestamp: Int(model.mostRecentZapCreatedAt)
                            )
                        )
                    )
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

//struct ZapAndZapFrom: Identifiable {
//    var id: String { zap.id }
//    let zap: Event
//    let zapFrom: Event
//}

struct ZapPill: View {
    @Environment(\.theme) private var theme
    public var nxZap: NxZap
    public var index: Int
    public var availableWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 5) {
            ObservedPFP(pubkey: nxZap.fromPubkey, size: 20.0, forceFlat: false)
            Text(nxZap.sats.satsFormatted)
                .foregroundColor(theme.accent)
                .padding(.trailing, 5)
            if index < 3, let content = nxZap.nrZapFrom.content {
                Text(content)
                    .padding(.trailing, 5)
                    .lineLimit(1)
            }
        }
        .background(theme.listBackground.opacity(0.5))
        .foregroundColor(theme.primary)
        .font(.footnote)
        .clipShape(Capsule())
        .frame(
            maxWidth: index == 0 ? availableWidth : ((availableWidth-20) / 2)
        )
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadZaps()
    }) {
        TopZaps(
            id: "7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565"
        )
    }
}
