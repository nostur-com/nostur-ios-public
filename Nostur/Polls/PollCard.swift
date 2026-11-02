import SwiftUI
import NavigationBackport

struct PollCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.nxViewingContext) private var viewingContext
    @ObservedObject private var accounts = AccountsState.shared
    @StateObject private var model: PollViewModel
    @State private var selection = Set<String>()
    @State private var viewingResults = false
    @State private var changingVote = false
    @State private var showVoters = false
    @State private var selectedOption: String?
    @State private var showPrivacy = false
    @State private var attemptedVote = false
    private let isDetail: Bool

    init(nrPost: NRPost, isDetail: Bool = false) {
        let tags = nrPost.fastTags.map { tag -> [String] in
            var values = [tag.0, tag.1]
            if let value = tag.2 { values.append(value) }
            return values
        }
        let poll = NostrPoll(id: nrPost.id, createdAt: Int(nrPost.created_at), tags: tags)
        self.init(poll: poll, authorPubkey: nrPost.pubkey, isDetail: isDetail)
    }

    init(poll: NostrPoll, authorPubkey: String? = nil, isDetail: Bool = false) {
        self.isDetail = isDetail
        let model = PollViewModel.model(for: poll)
        if let authorPubkey { model.rememberAuthor(authorPubkey) }
        _model = StateObject(wrappedValue: model)
    }

    private var accountPubkey: String { accounts.activeAccountPublicKey }
    private var ownVote: PollVote? { model.tally.votes.first { $0.pubkey == accountPubkey } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let ended = model.poll.hasEnded(at: Int(timeline.date.timeIntervalSince1970))
            let results = ended || (!changingVote && (viewingResults || ownVote != nil))
            VStack(alignment: .leading, spacing: 10) {
                if model.poll.isSupported {
                    ForEach(model.poll.options) { option in
                        if results { resultRow(option) }
                        else { optionRow(option) }
                    }
                    if !results { votingActions }
                    footer(ended: ended, showingResults: results)
                } else {
                    Text("This poll has invalid or unsupported settings.")
                        .font(.callout).foregroundStyle(theme.secondary)
                }
            }
            .padding(.vertical, 10)
        }
        // List offers a taller row proposal than ScrollView. Keep the timeline and
        // its button labels at their content height instead of stretching the footer.
        .fixedSize(horizontal: false, vertical: true)
        .task(id: accountPubkey) {
            selection = []
            attemptedVote = false
            changingVote = false
            viewingResults = false
            guard !viewingContext.contains(.preview), !viewingContext.contains(.screenshot) else { return }
            await model.load(accountPubkey: accountPubkey)
        }
        .sheet(isPresented: $showVoters) {
            PollVotersSheet(model: model, selectedOption: selectedOption, dismissSheet: { showVoters = false })
        }
        .alert("Votes are public", isPresented: $showPrivacy) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your account and selected answers are public on Nostr. Changing your vote updates the results, but earlier votes can remain public.")
        }
    }

    private var votingActions: some View {
        HStack(spacing: 24) {
            Button {
                selection = []
                changingVote = false
                viewingResults = true
            } label: {
                Text(changingVote ? "Cancel" : "View results")
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button {
                let selected = selection
                attemptedVote = true
                Task {
                    if await model.vote(selection: selected, accountPubkey: accountPubkey) {
                        changingVote = false
                        viewingResults = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isPublishing { ProgressView() }
                    Text("Vote")
                }
                .frame(minWidth: 64, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty || model.isPublishing || model.isLoading || !model.hasLoaded)
        }
    }

    private func privacyButton(iconOnly: Bool) -> some View {
        Button { showPrivacy = true } label: {
            Group {
                if iconOnly {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .frame(width: 44, height: 44)
                } else {
                    Label("Votes are public", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .frame(minHeight: 44)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondary)
        .accessibilityLabel("Votes are public")
    }

    private var refreshButton: some View {
        Button {
            Task { await model.load(accountPubkey: accountPubkey, force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading)
        .accessibilityLabel("Refresh poll results")
    }

    private func optionRow(_ option: NostrPoll.Option) -> some View {
        Button {
            if model.poll.multipleChoice {
                if !selection.insert(option.id).inserted { selection.remove(option.id) }
            } else { selection = [option.id] }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selection.contains(option.id)
                      ? (model.poll.multipleChoice ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (model.poll.multipleChoice ? "square" : "circle"))
                    .frame(width: 20)
                Text(option.label).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.listBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.contains(option.id) ? theme.accent : theme.lineColor))
        }
        .buttonStyle(.plain)
        .disabled(model.isPublishing)
        .accessibilityAddTraits(selection.contains(option.id) ? .isSelected : [])
    }

    private func resultRow(_ option: NostrPoll.Option) -> some View {
        let voters = model.tally.votersByOption[option.id] ?? []
        let fraction = model.tally.totalVoters == 0 ? 0 : Double(voters.count) / Double(model.tally.totalVoters)
        let follows = accounts.loggedInAccount?.followingPublicKeys ?? []
        let familiar = voters.filter { follows.contains($0.pubkey) || $0.pubkey == accountPubkey }
        let limit = availableWidth >= 600 ? 10 : (availableWidth >= 280 ? 5 : 3)
        let additionalFollowed = familiar.dropFirst(limit).filter { follows.contains($0.pubkey) }.count
        let isOwnChoice = ownVote?.responses.contains(option.id) == true
        return Button {
            selectedOption = option.id
            showVoters = true
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(option.label)
                        .font(.subheadline)
                        .fontWeight(isOwnChoice ? .semibold : .regular)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isOwnChoice {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .accessibilityLabel("Your choice")
                    }
                    Group {
                        if model.hasLoaded {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        } else {
                            Text("—").accessibilityLabel("Percentage unavailable")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
                }
                PollResultBar(fraction: model.hasLoaded ? fraction : nil,
                              isLoading: model.isLoading && !model.hasLoaded,
                              isOwnChoice: isOwnChoice)
                HStack(spacing: 0) {
                    HStack(spacing: -5) {
                        ForEach(Array(familiar.prefix(limit))) { voter in
                            ObservedPFP(pubkey: voter.pubkey, size: 18)
                                .overlay(Circle().stroke(theme.listBackground, lineWidth: 1.5))
                                .accessibilityHidden(true)
                        }
                    }
                    if additionalFollowed > 0 {
                        Text("+\(additionalFollowed) you follow")
                            .font(.caption2)
                            .foregroundStyle(theme.secondary)
                            .padding(.leading, 6)
                    }
                    Spacer(minLength: 12)
                    Group {
                        if model.hasLoaded {
                            if voters.count == 1 { Text("1 vote") }
                            else { Text("\(voters.count) votes") }
                        }
                        else { Text("—").accessibilityLabel("Vote count unavailable") }
                    }
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .monospacedDigit()
                }
                .frame(minHeight: 18)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footer(ended: Bool, showingResults: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        selectedOption = nil
                        showVoters = true
                    } label: {
                        HStack(spacing: 4) {
                            if model.hasLoaded {
                                if model.tally.totalVoters == 1 { Text("1 voter") }
                                else { Text("\(model.tally.totalVoters) voters") }
                            }
                            else { Text("Results") }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Show voters and their choices")
                    Text("·")
                    if ended { Text("Ended") }
                    else if let end = model.poll.endsAt {
                        Text("Ends \(Date(timeIntervalSince1970: TimeInterval(end)), style: .relative)")
                    } else { Text("No deadline") }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    if model.isLoading && (!showingResults || model.hasLoaded) {
                        ProgressView().controlSize(.small)
                            .frame(width: 44, height: 44)
                    } else if showingResults && !ended && model.hasLoaded {
                        // ImageRenderer draws Menu as a missing-image placeholder.
                        if viewingContext.contains(.screenshot) {
                            Image(systemName: "ellipsis")
                                .font(.body)
                                .frame(width: 44, height: 44)
                        } else {
                            Menu {
                                Button(ownVote == nil ? "Vote" : "Change vote") {
                                    selection = Set(ownVote?.responses ?? [])
                                    changingVote = true
                                }
                                Button {
                                    Task { await model.load(accountPubkey: accountPubkey, force: true) }
                                } label: {
                                    Label("Refresh results", systemImage: "arrow.clockwise")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Poll actions")
                        }
                    } else if isDetail {
                        refreshButton
                    }
                    privacyButton(iconOnly: showingResults)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if attemptedVote, let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .font(.caption).foregroundStyle(theme.secondary)
    }

}

struct PollResultBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double?
    let isLoading: Bool
    let isOwnChoice: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.lineColor.opacity(0.5))
                if let fraction {
                    Capsule().fill(theme.accent.opacity(isOwnChoice ? 0.9 : 0.5))
                        .frame(width: geometry.size.width * fraction)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
                } else if isLoading {
                    PollLoadingSweep(width: geometry.size.width)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "Loading results" : "Result bar")
    }
}

private struct PollLoadingSweep: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanning = false
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [theme.accent.opacity(0), theme.accent.opacity(0.8), theme.accent.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width * 0.3)
            .offset(x: reduceMotion ? width * 0.35 : (scanning ? width * 0.7 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: true), value: scanning)
            .onAppear { scanning = true }
    }
}

