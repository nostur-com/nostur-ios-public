//
//  Kind1984.swift
//  Nostur
//

import SwiftUI

struct ReportEventDetails: Equatable {
    enum Target: Equatable {
        case profile(pubkey: String)
        case event(id: String, pubkey: String?)
        case blob(hash: String, eventId: String?, pubkey: String?)
        case unknown
    }

    let target: Target
    let reason: String?
    let note: String?

    init(fastTags: [FastTag], content: String?) {
        let pTag = fastTags.first(where: { $0.0 == "p" })
        let eTag = fastTags.first(where: { $0.0 == "e" })
        let xTag = fastTags.first(where: { $0.0 == "x" })

        if let xTag {
            target = .blob(hash: xTag.1, eventId: eTag?.1, pubkey: pTag?.1)
            reason = xTag.2 ?? eTag?.2 ?? pTag?.2
        }
        else if let eTag {
            target = .event(id: eTag.1, pubkey: pTag?.1)
            reason = eTag.2 ?? pTag?.2
        }
        else if let pTag {
            target = .profile(pubkey: pTag.1)
            reason = pTag.2
        }
        else {
            target = .unknown
            reason = nil
        }

        let trimmedNote = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        note = trimmedNote?.isEmpty == false ? trimmedNote : nil
    }

    var targetPubkey: String? {
        switch target {
        case .profile(let pubkey): pubkey
        case .event(_, let pubkey), .blob(_, _, let pubkey): pubkey
        case .unknown: nil
        }
    }

    var reasonDescription: String {
        switch reason?.lowercased() {
        case "nudity": "Nudity or sexual content"
        case "malware": "Malicious software"
        case "profanity": "Profanity or hateful speech"
        case "illegal": "Illegal content"
        case "spam": "Spam"
        case "impersonation": "Impersonation"
        case "other": "Other"
        case .some(let reason): reason.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: "Reason not specified"
        }
    }
}

struct Kind1984: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth

    private let nrPost: NRPost
    private let details: ReportEventDetails
    @ObservedObject private var targetContact: NRContact

    private let hideFooter: Bool
    private let missingReplyTo: Bool
    private let connect: ThreadConnectDirection?
    private let isReply: Bool
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let forceAutoload: Bool

    init(
        nrPost: NRPost,
        hideFooter: Bool = true,
        missingReplyTo: Bool = false,
        connect: ThreadConnectDirection? = nil,
        isReply: Bool = false,
        isDetail: Bool = false,
        isEmbedded: Bool = false,
        fullWidth: Bool = false,
        forceAutoload: Bool = false
    ) {
        let details = ReportEventDetails(fastTags: nrPost.fastTags, content: nrPost.content)
        self.nrPost = nrPost
        self.details = details
        self.targetContact = NRContact.instance(of: details.targetPubkey ?? nrPost.pubkey)
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
        Group {
            if isEmbedded {
                PostEmbeddedLayout(nrPost: nrPost, authorAtBottom: true) {
                    reportContent
                }
            }
            else {
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
                    reportContent
                }
            }
        }
        .task {
            if let pubkey = details.targetPubkey {
                QueuedFetcher.shared.enqueue(pTag: pubkey)
            }
        }
        .onDisappear {
            if let pubkey = details.targetPubkey {
                QueuedFetcher.shared.dequeue(pTag: pubkey)
            }
        }
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "flag.fill")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(theme.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(details.reasonDescription) report")
                        .font(.headline)
                    Text(reportTargetDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            targetRow

            if let note = details.note {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reporter's note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.body)
                        .lineLimit(isDetail ? nil : 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var reportTargetDescription: String {
        switch details.target {
        case .profile: "Reported profile"
        case .event: "Reported post"
        case .blob: "Reported file"
        case .unknown: "Reported content"
        }
    }

    @ViewBuilder
    private var targetRow: some View {
        switch details.target {
        case .profile:
            targetButton(title: targetContact.anyName, subtitle: "View reported profile", systemImage: "person.crop.circle") {
                navigateToContact(pubkey: targetContact.pubkey, nrContact: targetContact, nrPost: nrPost, context: containerID)
            }
        case .event(let id, _):
            targetButton(title: targetName(fallback: "Reported post"), subtitle: "View reported post", systemImage: "text.bubble") {
                navigateTo(NotePath(id: id), context: containerID)
            }
        case .blob(_, let eventId, _):
            if let eventId {
                targetButton(title: targetName(fallback: "Reported file"), subtitle: "View post containing the reported file", systemImage: "doc") {
                    navigateTo(NotePath(id: eventId), context: containerID)
                }
            }
            else {
                targetButton(title: targetName(fallback: "Reported file"), subtitle: "Reported file", systemImage: "doc", action: nil)
            }
        case .unknown:
            Text("The report does not identify its target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func targetName(fallback: String) -> String {
        details.targetPubkey == nil ? fallback : targetContact.anyName
    }

    private func targetButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            guard !nxViewingContext.contains(.preview) else { return }
            action?()
        } label: {
            HStack(spacing: 10) {
                if details.targetPubkey != nil {
                    PFP(pubkey: targetContact.pubkey, pictureUrl: targetContact.pictureUrl, size: 34, forceFlat: nxViewingContext.contains(.screenshot))
                }
                else {
                    Image(systemName: systemImage)
                        .frame(width: 34, height: 34)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeightBold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
