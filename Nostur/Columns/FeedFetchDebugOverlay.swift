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
                Text("Fetch debug on. No fetch recorded yet for this column.")
                Text("A fetch will appear here after this feed loads. Tap Fetch now, or leave this tab and come back.")
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

            eventsLine

            Text(statusLine)
                .foregroundStyle(.white.opacity(0.85))

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
                VStack(alignment: .leading, spacing: 2) {
                    FeedFetchDebugRelayColumns.header(
                        relayCount: session.relays.count,
                        outboxCount: session.relays.count { $0.isOutbox }
                    )
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(sortedRelays) { row in
                                FeedFetchDebugRelayRowView(row: row, startedAt: session.startedAt)
                            }
                        }
                    }
                    .frame(maxHeight: relayListMaxHeight)
                }
            }
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
            Text("\(session.trigger) · \(barLabel) · \(elapsed, format: .number.precision(.fractionLength(2)))s · \(session.eoseCount)/\(session.relays.count) eose")
            Spacer(minLength: 8)
            Button("Fetch", action: onFetchNow)
            Button("Hide") {
                FeedFetchDebug.shared.setEnabled(false)
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
        let headerReserve: CGFloat = 96
        let rowHeight: CGFloat = 15
        let contentHeight = CGFloat(max(sortedRelays.count, 1)) * rowHeight + 8
        let available = max(maxHeight - headerReserve, 80)
        return min(contentHeight, available)
    }

    private var eventsLine: some View {
        HStack(spacing: 0) {
            Text("\(session.eventCount) events - \(session.acceptedOnScreen) new")
                .foregroundStyle(.white.opacity(0.85))
            if let lateSuffix {
                Text(lateSuffix)
                    .foregroundStyle(.cyan)
            }
        }
    }

    private var lateSuffix: String? {
        guard session.lateEventCount > 0, let lastLate = session.lastLateEventAt else { return nil }
        return String(format: " - +%d late @ %.2fs", session.lateEventCount, lastLate.timeIntervalSince(session.startedAt))
    }

    private var statusLine: String {
        let planned = session.targetSnapshot?.quarantinedCandidateCount ?? 0
        let total = session.targetSnapshot?.activeQuarantineCount ?? 0
        return "\(session.waitingCount) wait · quarantine \(planned) planned · \(total) total"
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

private enum RelayMetricTone {
    case normal
    case slow
    case bad
}

private enum RelayMetricThresholds {
    static let sentSlow: TimeInterval = 2.0
    static let sentBad: TimeInterval = 4.0
    static let firstSlow: TimeInterval = 2.0
    static let firstBad: TimeInterval = 4.0
    static let eoseSlow: TimeInterval = 2.0
    static let eoseBad: TimeInterval = 4.0
}

private enum FeedFetchDebugRelayColumns {
    static let kindWidth: CGFloat = 24
    static let sentWidth: CGFloat = 40
    static let evWidth: CGFloat = 32
    static let firstWidth: CGFloat = 40
    static let eoseWidth: CGFloat = 40
    static let noteWidth: CGFloat = 52
    static let spacing: CGFloat = 4

    static func header(relayCount: Int, outboxCount: Int) -> some View {
        HStack(spacing: spacing) {
            Text("\(relayCount) relays (\(outboxCount) outbox)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: kindWidth, alignment: .leading)
            Text("sent")
                .frame(width: sentWidth, alignment: .trailing)
            Text("ev")
                .frame(width: evWidth, alignment: .trailing)
            Text("1st")
                .frame(width: firstWidth, alignment: .trailing)
            Text("eose")
                .frame(width: eoseWidth, alignment: .trailing)
            Text("note")
                .frame(width: noteWidth, alignment: .leading)
        }
        .foregroundStyle(.white.opacity(0.45))
        .lineLimit(1)
    }
}

private struct FeedFetchDebugRelayRowView: View {
    let row: FeedFetchDebugRelayRow
    let startedAt: Date

    var body: some View {
        HStack(spacing: FeedFetchDebugRelayColumns.spacing) {
            Text(row.shortHost)
                .foregroundStyle(hostColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(kindLabel)
                .foregroundStyle(kindColor)
                .frame(width: FeedFetchDebugRelayColumns.kindWidth, alignment: .leading)
            metric(sentLabel, tone: sentTone, width: FeedFetchDebugRelayColumns.sentWidth)
            metric(evLabel, tone: evTone, width: FeedFetchDebugRelayColumns.evWidth)
            metric(firstLabel, tone: firstTone, width: FeedFetchDebugRelayColumns.firstWidth)
            metric(eoseLabel, tone: eoseTone, width: FeedFetchDebugRelayColumns.eoseWidth)
            Text(noteLabel)
                .foregroundStyle(noteColor)
                .lineLimit(1)
                .frame(width: FeedFetchDebugRelayColumns.noteWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ text: String, tone: RelayMetricTone, width: CGFloat) -> some View {
        Text(text)
            .foregroundStyle(dataColor(tone))
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private func dataColor(_ tone: RelayMetricTone) -> Color {
        switch tone {
        case .normal:
            .white.opacity(0.85)
        case .slow:
            .orange
        case .bad:
            .red
        }
    }

    private var sentSeconds: TimeInterval? { seconds(row.sentAt) }
    private var firstSeconds: TimeInterval? { seconds(row.firstEventAt) }
    private var eoseSeconds: TimeInterval? { seconds(row.eoseAt) }

    private func seconds(_ date: Date?) -> TimeInterval? {
        guard let date else { return nil }
        return date.timeIntervalSince(startedAt)
    }

    private func format(_ value: TimeInterval?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    private func tone(for value: TimeInterval?, slow: TimeInterval, bad: TimeInterval) -> RelayMetricTone {
        guard let value else { return .normal }
        if value >= bad { return .bad }
        if value >= slow { return .slow }
        return .normal
    }

    private var kindLabel: String {
        switch (row.isOutbox, row.isFirstConnection) {
        case (true, true): "o/n"
        case (true, false): "out"
        case (false, true): "new"
        case (false, false): ""
        }
    }

    private var kindColor: Color {
        if row.isOutbox { return .cyan }
        if row.isFirstConnection { return .orange }
        return .white.opacity(0.45)
    }

    private var sentLabel: String { format(sentSeconds) }
    private var evLabel: String { row.eventCount > 0 ? "\(row.eventCount)" : (row.eoseAt != nil || row.timedOut ? "0" : "") }
    private var firstLabel: String { format(firstSeconds) }
    private var eoseLabel: String { format(eoseSeconds) }

    private var sentTone: RelayMetricTone {
        if row.timedOut && row.sentAt == nil { return .bad }
        if row.queued && row.sentAt == nil && (row.abandoned || row.timedOut) { return .bad }
        return tone(for: sentSeconds, slow: RelayMetricThresholds.sentSlow, bad: RelayMetricThresholds.sentBad)
    }

    private var evTone: RelayMetricTone {
        if row.lateEventCount > 0 { return .slow }
        if row.eventCount > 0 { return .normal }
        if row.timedOut { return .bad }
        if row.eoseAt != nil { return .slow }
        return .normal
    }

    private var firstTone: RelayMetricTone {
        if row.timedOut && row.firstEventAt == nil && row.sentAt != nil { return .bad }
        return tone(for: firstSeconds, slow: RelayMetricThresholds.firstSlow, bad: RelayMetricThresholds.firstBad)
    }

    private var eoseTone: RelayMetricTone {
        if row.timedOut && row.eoseAt == nil { return .bad }
        if row.eoseAt != nil && row.eventCount == 0 {
            return worse(.slow, tone(for: eoseSeconds, slow: RelayMetricThresholds.eoseSlow, bad: RelayMetricThresholds.eoseBad))
        }
        return tone(for: eoseSeconds, slow: RelayMetricThresholds.eoseSlow, bad: RelayMetricThresholds.eoseBad)
    }

    private func worse(_ lhs: RelayMetricTone, _ rhs: RelayMetricTone) -> RelayMetricTone {
        switch (lhs, rhs) {
        case (.bad, _), (_, .bad): .bad
        case (.slow, _), (_, .slow): .slow
        default: .normal
        }
    }

    private var noteLabel: String {
        if row.lateEventCount > 0 { return "late" }
        if row.timedOut {
            if row.sentAt == nil {
                return row.isConnected ? "nosend" : "nocon"
            }
            return "timeout"
        }
        if row.abandoned { return "skip" }
        if row.lingerEnded {
            if row.sentAt != nil { return "closed" }
            if row.queued { return "nosend" }
            return "nocon"
        }
        if row.closed && row.eoseAt == nil { return "closed" }
        if row.eoseAt != nil && row.eventCount == 0 { return "empty" }
        if row.eoseAt != nil { return "" }
        if row.sentAt != nil { return "wait" }
        if row.queued { return "queue" }
        if row.isConnecting { return "conn" }
        if row.isConnected { return "idle" }
        return "idle"
    }

    private var noteColor: Color {
        switch noteLabel {
        case "timeout", "nosend", "nocon", "closed":
            .red
        case "empty", "queue", "conn":
            .orange
        case "late", "wait":
            .cyan
        case "skip", "idle":
            .white.opacity(0.45)
        default:
            .white.opacity(0.85)
        }
    }

    private var hostColor: Color {
        if row.timedOut { return .red.opacity(0.95) }
        if row.lingerEnded && row.sentAt == nil { return .red.opacity(0.85) }
        if row.abandoned || row.lingerEnded { return .white.opacity(0.45) }
        return .white
    }
}
#endif
