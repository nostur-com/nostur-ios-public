import SwiftUI
import NavigationBackport

private enum PollResultsScope: Hashable {
    case everyone, webOfTrust, following
}

struct PollVotersSheet: View {
    private let dismissSheet: () -> Void
    @ObservedObject var model: PollViewModel
    @State private var path: [String]
    @State private var scope: PollResultsScope = .everyone

    init(model: PollViewModel, selectedOption: String?, dismissSheet: @escaping () -> Void) {
        self.model = model
        self.dismissSheet = dismissSheet
        _path = State(initialValue: selectedOption.map { [$0] } ?? [])
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                page(optionID: nil)
                    .navigationDestination(for: String.self) { page(optionID: $0) }
            }
            .presentationDetents([.large])
        } else {
            NBNavigationStack(path: $path) {
                page(optionID: nil)
                    .nbNavigationDestination(for: String.self) { page(optionID: $0) }
            }
            .nbUseNavigationStack(.never)
        }
    }

    private func page(optionID: String?) -> some View {
        PollVotersPage(model: model, scope: $scope, selectedOption: optionID,
                       openOption: { path.append($0) }, dismissSheet: dismissSheet)
    }
}

/// Derive results inside each destination so changes remain live after a push.
private struct PollVotersPage: View {
    @ObservedObject var model: PollViewModel
    @Binding var scope: PollResultsScope
    let selectedOption: String?
    let openOption: (String) -> Void
    let dismissSheet: () -> Void
    @ObservedObject private var wot = WebOfTrust.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var accounts = AccountsState.shared

    var body: some View {
        let membership: WebOfTrust.Membership = scope == .webOfTrust
            ? wot.membership(of: Set(model.tally.votes.map(\.pubkey))) : .disabled
        PollVotersContent(model: model, tally: scopedTally(membership: membership), scope: $scope,
                          unavailable: unavailableMessage(membership: membership), selectedOption: selectedOption,
                          openOption: openOption, dismissSheet: dismissSheet)
    }

    private func scopedTally(membership: WebOfTrust.Membership) -> PollTally {
        switch scope {
        case .everyone: return model.tally
        case .following:
            return model.tally.filtered(to: accounts.loggedInAccount?.followingPublicKeys ?? [])
        case .webOfTrust:
            if case .ready(let keys) = membership { return model.tally.filtered(to: keys) }
            return model.tally.filtered(to: [])
        }
    }

    private func unavailableMessage(membership: WebOfTrust.Membership) -> LocalizedStringKey? {
        guard scope == .webOfTrust else { return nil }
        switch membership {
        case .disabled: return "Enable Web of Trust in Settings to see these results."
        case .loading: return "Your Web of Trust is still loading."
        case .ready: return nil
        }
    }

}

private struct PollVotersContent: View {
    @Environment(\.containerID) private var containerID
    @Environment(\.theme) private var theme
    @ObservedObject var model: PollViewModel
    let tally: PollTally
    @Binding var scope: PollResultsScope
    let unavailable: LocalizedStringKey?
    let selectedOption: String?
    let openOption: (String) -> Void
    let dismissSheet: () -> Void
    @State private var showPublicVotesInfo = false

    private var voters: [PollVote] {
        tally.voters(for: selectedOption)
    }

    private var emptyMessage: LocalizedStringKey {
        switch scope {
        case .everyone: return "No votes yet."
        case .webOfTrust: return "No votes from people in your Web of Trust."
        case .following: return "No votes from people you follow."
        }
    }

    private var voterTotal: LocalizedStringKey {
        let count = selectedOption == nil ? tally.totalVoters : voters.count
        switch scope {
        case .everyone:
            return count == 1 ? "1 voter" : "\(count) voters"
        case .webOfTrust:
            return count == 1 ? "1 voter in your Web of Trust" : "\(count) voters in your Web of Trust"
        case .following:
            return count == 1 ? "1 voter you follow" : "\(count) voters you follow"
        }
    }

    private var visibleOptions: [NostrPoll.Option] {
        guard let selectedOption else { return model.poll.options }
        return model.poll.options.filter { $0.id == selectedOption }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let unavailable {
                    Text(unavailable)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                        .padding(.vertical, 24)
                } else {
                    overview
                        .padding(.bottom, 24)

                    Text("Voters")
                        .font(.headline)
                        .padding(.bottom, 12)

                    Group {
                        ForEach(voters) { voter in
                            voterRow(voter)
                            Divider().padding(.leading, 48)
                        }

                        if voters.isEmpty {
                            if model.isLoading && !model.hasLoaded {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                            } else {
                                Text(emptyMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 32)
                            }
                        }
                    }

                }

                if model.error != nil || model.poll.multipleChoice {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = model.error { Text(error) }
                        if model.poll.multipleChoice {
                            Text("People can choose more than one answer, so percentages can add up to more than 100%.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .padding(.top, 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Results from", selection: $scope) {
                Text("Everyone").tag(PollResultsScope.everyone)
                Text("Web of Trust").tag(PollResultsScope.webOfTrust)
                Text("Following").tag(PollResultsScope.following)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(theme.listBackground)
        }
        .background(theme.listBackground)
        .navigationTitle(selectedOption == nil ? "Poll results" : "Voters")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Votes are public", isPresented: $showPublicVotesInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Anyone who receives a vote can see the voting account and its chosen answers. Web of Trust and Following only filter these results; they do not make votes private. Earlier votes may remain public after a vote changes.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismissSheet() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss poll results")
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if model.hasLoaded {
                        Text(voterTotal)
                            .monospacedDigit()
                    } else {
                        Text("Votes")
                    }
                    refreshVotesButton
                    Spacer(minLength: 8)
                    Button { showPublicVotesInfo = true } label: {
                        Label("Public votes", systemImage: "info.circle")
                            .labelStyle(.titleAndIcon)
                            .frame(minHeight: PollResultsLayout.summaryControlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About public votes")
                    .help("About public votes")
                }
                .font(.caption)
                .foregroundStyle(theme.secondary)

                PollResultsSourcesView(model: model)
            }

            ForEach(visibleOptions) { option in
                if selectedOption == nil {
                    Button { openOption(option.id) } label: { answerRow(option) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Show people who chose this answer")
                } else {
                    answerRow(option)
                }
            }
        }
    }

    private var refreshVotesButton: some View {
        Button {
            Task {
                await model.load(accountPubkey: AccountsState.shared.activeAccountPublicKey, force: true)
            }
        } label: {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .opacity(model.isLoading ? 0 : 1)
                if model.isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .frame(width: PollResultsLayout.summaryControlHeight, height: PollResultsLayout.summaryControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading)
        .accessibilityLabel("Refresh votes")
        .help("Refresh votes")
    }

    private func answerRow(_ option: NostrPoll.Option) -> some View {
        let count = tally.votersByOption[option.id]?.count ?? 0
        let fraction = tally.totalVoters == 0 ? 0 : Double(count) / Double(tally.totalVoters)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Group {
                    if model.hasLoaded {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    } else { Text("—") }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primary)
                .monospacedDigit()
                .fixedSize()
            }
            PollResultBar(fraction: model.hasLoaded ? fraction : nil,
                          isLoading: model.isLoading && !model.hasLoaded, isOwnChoice: false)
            HStack {
                if model.hasLoaded {
                    if count == 1 { Text("1 vote") }
                    else { Text("\(count) votes") }
                }
                Spacer()
                if selectedOption == nil {
                    Image(systemName: "chevron.right")
                }
            }
            .font(.caption)
            .foregroundStyle(theme.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func voterRow(_ voter: PollVote) -> some View {
        Button {
            dismissSheet()
            navigateTo(ContactPath(key: voter.pubkey), context: containerID)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ObservedPFP(pubkey: voter.pubkey, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    ContactName(pubkey: voter.pubkey)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                    if selectedOption == nil {
                        Text(model.poll.options.filter { voter.responses.contains($0.id) }.map(\.label).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(theme.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Text(Date(timeIntervalSince1970: TimeInterval(voter.createdAt)).agoString)
                    .font(.caption2)
                    .foregroundStyle(theme.secondary)
                    .fixedSize()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open profile")
    }
}
