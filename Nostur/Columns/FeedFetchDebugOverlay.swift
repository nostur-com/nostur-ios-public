//
//  FeedFetchDebugOverlay.swift
//  Nostur
//
//  Compact per-column feed-fetch overlay. DEBUG only. Toggle with the DBG button.
//

#if DEBUG
import SwiftUI

struct FeedFetchDebugOverlay: View {
    @ObservedObject var speedTest: NXSpeedTest
    var onFetchNow: () -> Void
    @ObservedObject private var hub = FeedFetchDebug.shared

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear
                    .frame(minHeight: geo.size.height * 0.28)
                    .allowsHitTesting(false)
                panel(maxHeight: geo.size.height * 0.70)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func panel(maxHeight: CGFloat) -> some View {
        if let session = speedTest.debugSession {
            FeedFetchDebugSessionView(
                session: session,
                barState: speedTest.loadingBarViewState,
                onFetchNow: onFetchNow,
                maxHeight: maxHeight
            )
        }
        else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Fetch debug on. No fetch recorded yet.")
                Text("This feed does not use pull-to-refresh. Tap Fetch now, or leave this tab and come back.")
                    .foregroundStyle(.white.opacity(0.7))
                Button("Fetch now", action: onFetchNow)
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption2.monospaced())
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.78))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

private struct FeedFetchDebugSessionView: View {
    @ObservedObject var session: FeedFetchDebugSession
    let barState: LoadingBar.ViewState
    var onFetchNow: () -> Void
    var maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow()

            Text(headerLine)
                .foregroundStyle(.white.opacity(0.85))

            if let outboxLine {
                Text(outboxLine)
                    .foregroundStyle(.cyan.opacity(0.85))
            }

            if let reqSummary = session.reqSummary {
                Text(reqSummary)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Divider().overlay(Color.white.opacity(0.25))

            if session.relays.isEmpty {
                Text("No relays attached yet")
                    .foregroundStyle(.white.opacity(0.65))
            }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedRelays) { row in
                            FeedFetchDebugRelayRowView(row: row, startedAt: session.startedAt)
                        }
                    }
                }
                .frame(maxHeight: relayListMaxHeight)
            }

            Text("Tap DBG to hide")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 2)
        }
        .font(.caption2.monospaced())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                panelBackground(at: context.date)
            }
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private enum FetchHealth {
        case ok
        case slow
        case bad
    }

    private func elapsed(at now: Date) -> TimeInterval {
        (session.endedAt ?? now).timeIntervalSince(session.startedAt)
    }

    private func health(at now: Date) -> FetchHealth {
        worse(coreHealth(at: now), extraHealth())
    }

    private func coreHealth(at now: Date) -> FetchHealth {
        let core = session.relays.filter { !$0.isOutbox }
        let coreEose = core.filter { $0.eoseAt != nil }
        let coreFailed = core.filter { $0.timedOut || ($0.sentAt == nil && $0.abandoned) }
        let seconds = elapsed(at: now)
        let slowestCoreEose = coreEose.compactMap { $0.eoseAt }.map {
            $0.timeIntervalSince(session.startedAt)
        }.max() ?? 0

        if barState == .timeout && coreEose.isEmpty {
            return .bad
        }
        if !core.isEmpty && coreEose.isEmpty && (isComplete || seconds >= 5) {
            return .bad
        }
        if !core.isEmpty && !coreFailed.isEmpty && coreFailed.count * 2 >= core.count {
            return .bad
        }
        if !coreFailed.isEmpty || slowestCoreEose >= 2.0 {
            return .slow
        }
        if !isComplete && seconds >= 3 && coreEose.isEmpty {
            return .slow
        }
        return .ok
    }

    /// Autopilot extras are noisy. The worst 30% may time out without
    /// changing the color. Failures beyond that budget count.
    private func extraHealth() -> FetchHealth {
        let extras = session.relays.filter(\.isOutbox)
        guard extras.count >= 3 else { return .ok }
        let failed = extras.filter { $0.timedOut }.count
        let allowed = Int((Double(extras.count) * 0.30).rounded(.down))
        let excess = failed - allowed
        guard excess > 0 else { return .ok }
        let remaining = extras.count - allowed
        if remaining > 0 && Double(excess) / Double(remaining) >= 0.5 {
            return .bad
        }
        return .slow
    }

    private func worse(_ lhs: FetchHealth, _ rhs: FetchHealth) -> FetchHealth {
        switch (lhs, rhs) {
        case (.bad, _), (_, .bad):
            .bad
        case (.slow, _), (_, .slow):
            .slow
        default:
            .ok
        }
    }

    private func panelBackground(at now: Date) -> Color {
        switch health(at: now) {
        case .ok:
            Color.black.opacity(0.82)
        case .slow:
            Color(red: 0.52, green: 0.40, blue: 0.06).opacity(0.92)
        case .bad:
            Color(red: 0.52, green: 0.10, blue: 0.10).opacity(0.92)
        }
    }

    @ViewBuilder
    private func headerRow() -> some View {
        if session.endedAt != nil || isComplete {
            headerContent(elapsed: frozenElapsed)
        }
        else {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                headerContent(elapsed: context.date.timeIntervalSince(session.startedAt))
            }
        }
    }

    private func headerContent(elapsed: TimeInterval) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(session.trigger) · \(barLabel) · \(elapsed, format: .number.precision(.fractionLength(2)))s")
            Spacer(minLength: 8)
            Button("Fetch", action: onFetchNow)
            Button("Hide") {
                FeedFetchDebug.shared.isEnabled = false
            }
            .font(.caption2.weight(.semibold))
        }
    }

    private var isComplete: Bool {
        switch barState {
        case .finished, .timeout, .off, .finalLoad:
            true
        default:
            false
        }
    }

    private var frozenElapsed: TimeInterval {
        let end = session.endedAt ?? Date()
        return end.timeIntervalSince(session.startedAt)
    }

    private var barLabel: String {
        switch barState {
        case .off: return "off"
        case .starting: return "starting"
        case .connecting: return "connecting"
        case .fetching: return "fetching"
        case .earlyLoad: return "earlyLoad"
        case .secondFetching: return "secondFetching"
        case .finalLoad: return "finalLoad"
        case .finished: return "finished"
        case .timeout: return "timeout"
        }
    }

    private var relayListMaxHeight: CGFloat {
        let headerReserve: CGFloat = session.targetSnapshot == nil ? 110 : 180
        let rowHeight: CGFloat = 18
        let contentHeight = CGFloat(max(sortedRelays.count, 1)) * rowHeight + 8
        let available = max(maxHeight - headerReserve, 80)
        return min(contentHeight, available)
    }

    private var headerLine: String {
        let sub = session.subscriptionId ?? "(no REQ yet)"
        return "\(sub) · \(session.eoseCount)/\(session.relays.count) eose · \(session.eventCount) ev · \(session.acceptedOnScreen) new · \(session.waitingCount) wait"
    }

    private var outboxLine: String? {
        guard let snapshot = session.targetSnapshot else { return nil }
        let selected = snapshot.extraIds.count
        let state = outboxStateLabel(snapshot.outboxPlanState)
        if snapshot.outboxPlanState == .planned {
            return "outbox \(state) · \(selected) destinations / \(snapshot.outboxRawRelayCount) raw · cap \(snapshot.outboxRelayLimit)\nauthors \(snapshot.outboxSelectedAuthorCount) selected / \(snapshot.outboxKnownAuthorCount) known / \(snapshot.outboxRequestedAuthorCount) requested\nquarantine \(snapshot.quarantinedCandidateCount) planned · \(snapshot.activeQuarantineCount) total"
        }
        return "outbox \(state) · 0 selected · q \(snapshot.activeQuarantineCount) total"
    }

    private func outboxStateLabel(_ state: ConnectionPool.RequestTargetSnapshot.OutboxPlanState) -> String {
        switch state {
        case .notRequested: "not requested"
        case .limitedToSelectedRelays: "selected relays only"
        case .lowDataMode: "blocked: low data"
        case .disabled: "disabled"
        case .vpnBlocked: "blocked: VPN"
        case .preferredRelaysUnavailable: "waiting for relay lists"
        case .noFindEventRelays: "no find-event relays"
        case .missingFilters: "missing filters"
        case .missingAuthors: "missing authors"
        case .planned: "planned"
        }
    }

    private var sortedRelays: [FeedFetchDebugRelayRow] {
        session.relays.sorted { lhs, rhs in
            let left = lhs.eoseAt ?? lhs.firstEventAt ?? lhs.sentAt ?? .distantFuture
            let right = rhs.eoseAt ?? rhs.firstEventAt ?? rhs.sentAt ?? .distantFuture
            if left != right { return left < right }
            return lhs.shortHost < rhs.shortHost
        }
    }
}

private struct FeedFetchDebugRelayRowView: View {
    let row: FeedFetchDebugRelayRow
    let startedAt: Date

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(row.shortHost)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 32, maxWidth: .infinity, alignment: .leading)
            if row.isOutbox {
                Text("out")
                    .foregroundStyle(.cyan)
                    .fixedSize()
            }
            if row.isFirstConnection {
                Text("new")
                    .foregroundStyle(.orange)
                    .fixedSize()
            }
            Text(detail)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColor: Color {
        if row.timedOut { return .red }
        if row.abandoned { return .gray }
        if row.eoseAt != nil { return row.eventCount == 0 ? .yellow : .green }
        if row.firstEventAt != nil { return .green }
        if row.sentAt != nil { return .white }
        if row.queued || row.isConnecting { return .blue }
        return .gray
    }

    private var detail: String {
        var parts: [String] = []
        if let sent = row.elapsed(from: startedAt, row.sentAt) {
            parts.append("sent \(sent)")
        }
        else if row.queued {
            parts.append("queued, never sent")
        }
        else {
            parts.append(row.statusLabel)
        }
        if row.eventCount > 0 {
            parts.append("\(row.eventCount)ev")
        }
        if let first = row.elapsed(from: startedAt, row.firstEventAt) {
            parts.append("1st \(first)")
        }
        if let eose = row.elapsed(from: startedAt, row.eoseAt) {
            parts.append(row.eventCount == 0 ? "eose \(eose) empty" : "eose \(eose)")
        }
        if row.timedOut {
            if row.sentAt != nil {
                parts.append("no EOSE before deadline")
            }
            else if row.isConnected {
                parts.append("connected, no REQ sent")
            }
            else {
                parts.append("deadline before connect")
            }
        }
        else if row.abandoned {
            parts.append("skipped after quorum")
        }
        return parts.joined(separator: " · ")
    }
}
#endif
