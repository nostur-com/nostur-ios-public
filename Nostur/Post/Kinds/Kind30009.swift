//
//  Kind30009.swift
//  Nostur
//
//  NIP-58 badge definition (kind 30009) — embed and row presentation.
//

import SwiftUI
import Nuke
import NukeUI
import CoreData

struct Kind30009: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth

    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    private let hideFooter: Bool
    private let missingReplyTo: Bool
    private var connect: ThreadConnectDirection? = nil
    private let isReply: Bool
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool

    private var badgeName: String {
        nrPost.fastTags.first(where: { $0.0 == "name" })?.1
            ?? nrPost.eventTitle
            ?? nrPost.dTag
            ?? String(localized: "Unnamed badge")
    }

    private var badgeDescription: String? {
        let description = nrPost.fastTags.first(where: { $0.0 == "description" })?.1
            ?? nrPost.eventSummary
        guard let description, !description.isEmpty else { return nil }
        return description
    }

    private var artworkURL: URL? {
        badgeArtworkURL(from: nrPost.fastTags, targetWidth: 112)
    }

    init(
        nrPost: NRPost,
        hideFooter: Bool = true,
        missingReplyTo: Bool = false,
        connect: ThreadConnectDirection? = nil,
        isReply: Bool = false,
        isDetail: Bool = false,
        isEmbedded: Bool = false,
        fullWidth: Bool,
        forceAutoload: Bool = false
    ) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.fullWidth = fullWidth
        self.forceAutoload = forceAutoload
    }

    var body: some View {
        if isEmbedded {
            embeddedView
        } else {
            normalView
        }
    }

    @ViewBuilder
    private var normalView: some View {
        PostLayout(
            nrPost: nrPost,
            hideFooter: hideFooter,
            missingReplyTo: missingReplyTo,
            connect: connect,
            isReply: isReply,
            isDetail: isDetail,
            fullWidth: fullWidth,
            forceAutoload: forceAutoload,
            isItem: true,
            showsFooterForItem: !isDetail,
            nxViewingContext: nxViewingContext,
            containerID: containerID,
            theme: theme,
            availableWidth: availableWidth
        ) {
            badgeCard(iconSize: isDetail ? 96 : 72, descriptionLines: isDetail ? 6 : 3)
                .contentShape(Rectangle())
                .onTapGesture(perform: openBadgeDetail)
        }
    }

    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost, authorAtBottom: true) {
            badgeCard(iconSize: 64, descriptionLines: 2)
                .contentShape(Rectangle())
                .onTapGesture(perform: openBadgeDetail)
        }
    }

    @ViewBuilder
    private func badgeCard(iconSize: CGFloat, descriptionLines: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            badgeArtwork(size: iconSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Badge"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(badgeName)
                    .font(.headline)
                    .foregroundStyle(theme.primary)
                    .lineLimit(2)

                if let badgeDescription {
                    Text(badgeDescription)
                        .font(.body)
                        .foregroundStyle(theme.primary)
                        .lineLimit(descriptionLines)
                }

                // Issuer is already shown by PostEmbeddedLayout when embedded
                if !isEmbedded {
                    HStack(spacing: 5) {
                        Text("by", comment: "Prefix before badge issuer name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        PFP(
                            pubkey: nrPost.pubkey,
                            pictureUrl: nrContact.pictureUrl,
                            size: 16,
                            forceFlat: nxViewingContext.contains(.screenshot)
                        )
                        Text(nrContact.anyName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !nxViewingContext.contains(.preview) else { return }
                        navigateToContact(
                            pubkey: nrPost.pubkey,
                            nrContact: nrContact,
                            nrPost: nrPost,
                            context: containerID
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, isEmbedded ? 2 : 6)
    }

    @ViewBuilder
    private func badgeArtwork(size: CGFloat) -> some View {
        if let url = artworkURL {
            LazyImage(
                request: ImageRequest(
                    url: url,
                    processors: [.resize(width: size)],
                    options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                    userInfo: [.scaleKey: UIScreen.main.scale]
                )
            ) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else if state.isLoading {
                    ProgressView()
                } else {
                    placeholderArtwork(size: size)
                }
            }
            .pipeline(ImageProcessing.shared.badges)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
        } else {
            placeholderArtwork(size: size)
        }
    }

    private func placeholderArtwork(size: CGFloat) -> some View {
        Image(systemName: "seal")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func openBadgeDetail() {
        guard !nxViewingContext.contains(.preview) else { return }
        if let badge = badgeEventOnMain() {
            navigateTo(Badge(badge), context: containerID)
            return
        }
        // Fall back to naddr path so BadgeByNaddr can fetch if needed
        if let naddr = try? ShareableIdentifier(
            prefix: "naddr",
            kind: Int64(BadgeKinds.definition),
            pubkey: nrPost.pubkey,
            dTag: nrPost.dTag,
            relays: []
        ).bech32string {
            navigateTo(
                Naddr1Path(naddr1: naddr, navigationTitle: badgeName),
                context: containerID
            )
        } else {
            navigateTo(nrPost, context: containerID)
        }
    }

    private func badgeEventOnMain() -> Event? {
        guard let dTag = nrPost.dTag, !dTag.isEmpty else { return nil }
        return Event.fetchReplacableEvent(
            Int64(BadgeKinds.definition),
            pubkey: nrPost.pubkey,
            definition: dTag,
            context: DataProvider.shared().viewContext
        )
    }
}

/// Resolves a badge definition naddr and presents the full badge detail screen.
struct BadgeByNaddr: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var settings: SettingsStore

    public let naddr1: String
    public var navigationTitle: String? = nil
    public var navTitleHidden: Bool = false

    @StateObject private var vm = FetchVM<EventObjectIDBox>(timeout: 1.5, debounceTime: 0.05)

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            HStack(spacing: 5) {
                ProgressView()
                if vm.state == .altLoading {
                    Text("Trying more relays...")
                } else {
                    Text("Fetching...")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(theme.listBackground)
            .task { [weak vm] in
                startFetch(vm)
            }

        case .ready(let box):
            if let badge = try? DataProvider.shared().viewContext.existingObject(with: box.objectID) as? Event {
                BadgeDetailView(badge: badge)
            } else {
                Text("Unable to open badge")
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(theme.listBackground)
            }

        case .timeout:
            VStack(spacing: 8) {
                Text("Unable to fetch badge")
                Text("Retry")
                    .foregroundStyle(theme.accent)
                    .highPriorityGesture(
                        TapGesture().onEnded { [weak vm] in
                            vm?.state = .initializing
                        }
                    )
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(theme.listBackground)

        case .error(let error):
            Text(error)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(theme.listBackground)
        }
    }

    private func startFetch(_ vm: FetchVM<EventObjectIDBox>?) {
        guard let naddr = try? ShareableIdentifier(naddr1),
              let kind = naddr.kind,
              let pubkey = naddr.pubkey,
              let definition = naddr.eventId
        else {
            vm?.error("Invalid badge address")
            return
        }

        let fetchParams: FetchVM<EventObjectIDBox>.FetchParams = (
            prio: true,
            req: { [weak vm] taskId in
                bg().perform { [weak vm] in
                    guard let vm else { return }
                    if let event = Event.fetchReplacableEvent(
                        kind,
                        pubkey: pubkey,
                        definition: definition,
                        context: bg()
                    ) {
                        vm.ready(EventObjectIDBox(objectID: event.objectID))
                    } else {
                        req(RM.getArticle(
                            pubkey: pubkey,
                            kind: Int(kind),
                            definition: definition,
                            subscriptionId: taskId
                        ))
                    }
                }
            },
            onComplete: { [weak vm] _, event in
                guard let vm else { return }
                if case .ready = vm.state { return }

                if let event = event, event.aTag == naddr.aTag {
                    vm.ready(EventObjectIDBox(objectID: event.objectID))
                } else if let event = Event.fetchReplacableEvent(
                    kind,
                    pubkey: pubkey,
                    definition: definition,
                    context: bg()
                ) {
                    vm.ready(EventObjectIDBox(objectID: event.objectID))
                } else if settings.followRelayHints && vpnGuardOK()
                            && [.initializing, .loading].contains(vm.state) {
                    vm.altFetch()
                } else {
                    vm.timeout()
                }
            },
            altReq: { taskId in
                req(
                    RM.getArticle(
                        pubkey: pubkey,
                        kind: Int(kind),
                        definition: definition,
                        subscriptionId: taskId
                    ),
                    relayType: .SEARCH
                )
                guard let relay = naddr.relays.first else { return }
                ConnectionPool.shared.sendEphemeralMessage(
                    RM.getArticle(
                        pubkey: pubkey,
                        kind: Int(kind),
                        definition: definition,
                        subscriptionId: taskId
                    ),
                    relay: relay
                )
            }
        )
        vm?.setFetchParams(fetchParams)
        vm?.fetch()
    }
}

/// Lightweight box so FetchVM can hand an Event across contexts via objectID.
struct EventObjectIDBox: Hashable {
    let objectID: NSManagedObjectID
}

/// Destination that opens badge detail for a definition already loaded as NRPost.
struct BadgeDetailFromNRPost: View {
    let nrPost: NRPost
    @Environment(\.theme) private var theme
    @State private var badge: Event?

    var body: some View {
        Group {
            if let badge {
                BadgeDetailView(badge: badge)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.listBackground)
                    .task { resolveBadge() }
            }
        }
    }

    private func resolveBadge() {
        if let dTag = nrPost.dTag, !dTag.isEmpty,
           let event = Event.fetchReplacableEvent(
            Int64(BadgeKinds.definition),
            pubkey: nrPost.pubkey,
            definition: dTag,
            context: DataProvider.shared().viewContext
           ) {
            badge = event
            return
        }

        // Transfer from bg context if only present there
        let pubkey = nrPost.pubkey
        let dTag = nrPost.dTag ?? ""
        bg().perform {
            guard let event = Event.fetchReplacableEvent(
                Int64(BadgeKinds.definition),
                pubkey: pubkey,
                definition: dTag,
                context: bg()
            ) else { return }
            let objectID = event.objectID
            Task { @MainActor in
                badge = try? DataProvider.shared().viewContext.existingObject(with: objectID) as? Event
            }
        }
    }
}

func badgeArtworkURL(from fastTags: [FastTag], targetWidth: Int) -> URL? {
    let thumbs: [(url: String, width: Int?)] = fastTags.compactMap { tag in
        guard tag.0 == "thumb", !tag.1.isEmpty else { return nil }
        let width = tag.2?
            .split(separator: "x").first
            .flatMap { Int($0) }
        return (tag.1, width)
    }
    let best = thumbs.min {
        abs(($0.width ?? targetWidth) - targetWidth) < abs(($1.width ?? targetWidth) - targetWidth)
    }?.url ?? fastTags.first(where: { $0.0 == "image" })?.1
    return best.flatMap(URL.init(string:))
}
