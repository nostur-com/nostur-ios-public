import SwiftUI

enum PollResultsLayout {
    static let summaryControlHeight: CGFloat = IS_CATALYST ? 28 : 44
}

struct PollResultsSourcesView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var model: PollViewModel
    @State var expanded = false

    private var pendingCount: Int { model.sources.filter { $0.status == .pending }.count }
    private var failedCount: Int { model.sources.filter { $0.status == .failed }.count }
    private var checkedCount: Int {
        model.sources.filter { [.checked, .moreAvailable, .limited].contains($0.status) }.count
    }

    private var actions: [PollResultsRequest] {
        var result: [PollResultsRequest] = []
        if failedCount > 0 { result.append(.retryFailed) }
        if pendingCount > 0 { result.append(.moreRelays) }
        if model.sources.contains(where: { $0.status == .moreAvailable }) { result.append(.moreResponses) }
        return result
    }

    private var summary: String {
        if model.isLoading { return String(localized: "Checking relays…") }
        if checkedCount > 0 {
            let checked = checkedCount == 1 ? String(localized: "1 relay checked") : String(localized: "\(checkedCount) relays checked")
            if failedCount > 0 { return checked + " · " + String(localized: "\(failedCount) failed") }
            if model.sources.contains(where: { $0.status == .limited }) {
                return checked + " · " + String(localized: "limit reached")
            }
            return checked
        }
        if failedCount > 0 {
            return failedCount == 1 ? String(localized: "1 relay failed") : String(localized: "\(failedCount) relays failed")
        }
        if pendingCount > 0 {
            return pendingCount == 1 ? String(localized: "1 relay available") : String(localized: "\(pendingCount) relays available")
        }
        return String(localized: "No relays checked yet")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(summary)
                            .multilineTextAlignment(.leading)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: PollResultsLayout.summaryControlHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondary)
                .accessibilityLabel("Results sources")
                .accessibilityValue(summary)
                .accessibilityHint(expanded ? "Hide relay details" : "Show relay details")
                .help("Results sources")

                if let action = actions.first {
                    sourceAction(action, compact: true)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text("These checks apply to this poll. They do not change your relay settings or guarantee every vote has been found.")
                        .foregroundStyle(theme.secondary)
                    ForEach(model.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.id)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            HStack(alignment: .firstTextBaseline) {
                                Text(source.status == .failed ? (source.failure?.title ?? String(localized: "Relay check failed without a reason")) : statusText(source.status))
                                Spacer(minLength: 8)
                                if let checked = source.lastChecked {
                                    Text(checked, format: .dateTime.hour().minute())
                                        .accessibilityLabel("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                                }
                            }
                            .foregroundStyle(theme.secondary)
                            if source.status == .failed, let detail = source.failure?.detail, !detail.isEmpty {
                                Text(detail)
                                    .foregroundStyle(theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if model.sources.contains(where: { $0.status == .limited }) {
                        Text("A relay returned a full page without any new responses. Its remaining responses could not be retrieved; checking other relays may help.")
                            .foregroundStyle(theme.secondary)
                    }
                    ForEach(Array(actions.dropFirst().enumerated()), id: \.offset) { _, action in
                        sourceAction(action)
                    }
                }
                .padding(12)
                .background(theme.lineColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)
            }
        }
        .font(.caption)
    }

    private func actionTitle(_ request: PollResultsRequest) -> LocalizedStringKey {
        switch request {
        case .retryFailed:
            return failedCount == 1 ? "Retry 1 relay" : "Retry \(failedCount) relays"
        case .moreRelays:
            let next = min(pendingCount, PollRelayPlan.maximumForeign)
            return next == 1 ? "Check 1 more relay" : "Check \(next) more relays"
        case .moreResponses: return "Load more responses"
        case .refresh: return "Refresh votes"
        }
    }

    private func sourceAction(_ request: PollResultsRequest, compact: Bool = false) -> some View {
        Button {
            Task {
                await model.load(accountPubkey: AccountsState.shared.activeAccountPublicKey, force: true, request: request)
            }
        } label: {
            Text(actionTitle(request))
                .fontWeight(.medium)
                .fixedSize(horizontal: compact, vertical: true)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: PollResultsLayout.summaryControlHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
        .disabled(model.isLoading)
    }

    private func statusText(_ status: PollResultsSource.Status) -> String {
        switch status {
        case .pending: return String(localized: "Not checked")
        case .loading: return String(localized: "Checking…")
        case .checked: return String(localized: "Checked")
        case .failed: return String(localized: "Relay check failed without a reason")
        case .moreAvailable: return String(localized: "More responses available")
        case .limited: return String(localized: "Couldn’t retrieve another page")
        }
    }
}
