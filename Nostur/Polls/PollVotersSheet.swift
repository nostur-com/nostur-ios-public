import SwiftUI
import NavigationBackport

struct PollVotersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.containerID) private var containerID
    @Environment(\.theme) private var theme
    @ObservedObject var model: PollViewModel
    @State var selectedOption: String?
    @State private var followingOnly = false

    private var voters: [PollVote] {
        let all = selectedOption.flatMap { model.tally.votersByOption[$0] } ?? model.tally.votes
        let follows = AccountsState.shared.loggedInAccount?.followingPublicKeys ?? []
        return followingOnly ? all.filter { follows.contains($0.pubkey) } : all
    }

    private var visibleOptions: [NostrPoll.Option] {
        guard let selectedOption else { return model.poll.options }
        return model.poll.options.filter { $0.id == selectedOption }
    }

    var body: some View {
        NBNavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        overview
                            .padding(.bottom, 24)
                        .id("poll-results-top")

                        HStack(alignment: .firstTextBaseline) {
                            Text("Voters").font(.headline)
                            Spacer()
                            if model.hasLoaded {
                                Text(voters.count, format: .number)
                                    .font(.subheadline).monospacedDigit()
                                    .foregroundStyle(theme.secondary)
                            }
                        }
                        .padding(.bottom, 12)

                        Picker("Voters", selection: $followingOnly) {
                            Text("Everyone").tag(false)
                            Text("Following").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)

                        ForEach(voters) { voter in
                            voterRow(voter)
                            Divider().padding(.leading, 48)
                        }

                        if voters.isEmpty {
                            if model.isLoading && !model.hasLoaded {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                            } else {
                                Text(followingOnly ? "No votes from people you follow." : "No votes yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 32)
                            }
                        }

                        if model.isPartial || model.error != nil || model.poll.multipleChoice {
                            VStack(alignment: .leading, spacing: 8) {
                                if model.isPartial {
                                    Label("Some responses may be missing from these results.", systemImage: "exclamationmark.circle")
                                }
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
                    .padding(16)
                }
                .onChange(of: selectedOption) { _ in
                    proxy.scrollTo("poll-results-top", anchor: .top)
                }
            }
            .background(theme.listBackground)
            .navigationTitle("Poll results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await model.load(accountPubkey: AccountsState.shared.activeAccountPublicKey, force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Refresh poll results")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Done")
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if selectedOption != nil {
                Button {
                    selectedOption = nil
                } label: {
                    Label("All answers", systemImage: "chevron.left")
                        .font(.subheadline)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }

            HStack {
                if model.hasLoaded {
                    if model.tally.totalVoters == 1 { Text("1 voter") }
                    else { Text("\(model.tally.totalVoters) voters") }
                }
                Spacer()
                Label("Public votes", systemImage: "person.crop.circle")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption)
            .foregroundStyle(theme.secondary)

            ForEach(visibleOptions) { option in
                answerRow(option)
            }
        }
    }

    private func answerRow(_ option: NostrPoll.Option) -> some View {
        let count = model.tally.votersByOption[option.id]?.count ?? 0
        let fraction = model.tally.totalVoters == 0 ? 0 : Double(count) / Double(model.tally.totalVoters)
        return Button {
            selectedOption = option.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
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
        .buttonStyle(.plain)
        .accessibilityHint("Show people who chose this answer")
    }

    private func voterRow(_ voter: PollVote) -> some View {
        Button {
            dismiss()
            navigateTo(ContactPath(key: voter.pubkey), context: containerID)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ObservedPFP(pubkey: voter.pubkey, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    ContactName(pubkey: voter.pubkey)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                    Text(model.poll.options.filter { voter.responses.contains($0.id) }.map(\.label).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                        .multilineTextAlignment(.leading)
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
