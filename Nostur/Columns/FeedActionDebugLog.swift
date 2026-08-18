//
//  FeedActionDebugLog.swift
//  Nostur
//
//  Lightweight rolling log for diagnosing feed viewport jumps. DEBUG only.
//

#if DEBUG
import SwiftUI
import UIKit

@MainActor
final class FeedActionDebugLog: ObservableObject {
    enum MeasurementKind: Equatable {
        case firstPosts
        case firstUnread
    }

    enum FirstRenderRating: Equatable {
        case fast
        case slow
        case failed
    }

    enum FirstRenderOutcome: Equatable {
        case posts
        case noNewPosts
        case timedOut
    }

    struct FirstRenderMetric {
        let duration: TimeInterval
        let postCount: Int
        let outcome: FirstRenderOutcome

        init(
            duration: TimeInterval,
            postCount: Int,
            outcome: FirstRenderOutcome = .posts
        ) {
            self.duration = duration
            self.postCount = postCount
            self.outcome = outcome
        }

        var rating: FirstRenderRating {
            if outcome == .timedOut { return .failed }
            if duration < 2 { return .fast }
            if duration < 4 { return .slow }
            return .failed
        }

        var formattedDuration: String {
            String(format: "%.2f", duration)
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String

        var line: String {
            "\(Self.timeFormatter.string(from: date))  \(message)"
        }

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    private static let visibilityKey = "feed_action_debug_overlay"
    private static let maximumEntries = 60
    private static let maximumFirstRenderEntries = 24

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var firstRenderEntries: [Entry] = []
    @Published private(set) var isVisible: Bool
    @Published private(set) var firstRenderMetric: FirstRenderMetric?
    @Published private(set) var isMeasuringFirstRender = false
    private var firstRenderStartedAt: Date?
    private var measurementKind: MeasurementKind = .firstPosts
    private var restoredPostsDuringMeasurement = false

    init() {
        if UserDefaults.standard.object(forKey: Self.visibilityKey) == nil {
            isVisible = true
        } else {
            isVisible = UserDefaults.standard.bool(forKey: Self.visibilityKey)
        }
    }

    func beginFirstRenderMeasurement(
        currentPostCount: Int,
        kind: MeasurementKind,
        at date: Date = Date()
    ) {
        firstRenderEntries.removeAll(keepingCapacity: true)
        measurementKind = kind
        restoredPostsDuringMeasurement = false
        if kind == .firstPosts, currentPostCount > 0 {
            firstRenderStartedAt = nil
            isMeasuringFirstRender = false
            firstRenderMetric = FirstRenderMetric(duration: 0, postCount: currentPostCount)
        } else {
            firstRenderStartedAt = date
            isMeasuringFirstRender = true
            firstRenderMetric = nil
        }
    }

    func record(_ message: String, at date: Date = Date()) {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.recordNow(message, at: date)
        }
    }

    private func recordNow(_ message: String, at date: Date) {
        let entry = Entry(date: date, message: message)
        entries.append(entry)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        if isMeasuringFirstRender {
            firstRenderEntries.append(entry)
            if firstRenderEntries.count > Self.maximumFirstRenderEntries {
                firstRenderEntries.removeFirst(firstRenderEntries.count - Self.maximumFirstRenderEntries)
            }
        }
        completeFirstRenderMeasurementIfNeeded(message: message, at: date)
    }

    /// Deterministic hook for parser/timing tests. Production recording stays
    /// deferred by one actor turn to avoid publishing during a SwiftUI update.
    func recordSynchronouslyForTesting(_ message: String, at date: Date) {
        recordNow(message, at: date)
    }

    func show() {
        setVisible(true)
    }

    func hide() {
        setVisible(false)
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        firstRenderEntries.removeAll(keepingCapacity: true)
        firstRenderStartedAt = nil
        isMeasuringFirstRender = false
        firstRenderMetric = nil
        restoredPostsDuringMeasurement = false
    }

    func report(feedName: String, currentState: String) -> String {
        let actionLines = entries.isEmpty
            ? "(no feed actions recorded yet)"
            : entries.map(\.line).joined(separator: "\n")
        let firstRenderLines = firstRenderEntries.isEmpty
            ? "(no first-render actions recorded)"
            : firstRenderEntries.map(\.line).joined(separator: "\n")
        return """
        Feed action log: \(feedName)
        \(measurementTitle.capitalized): \(firstRenderReport)
        First-render trace:
        \(firstRenderLines)
        Current: \(currentState)
        Last \(entries.count) actions:
        \(actionLines)
        """
    }

    private var firstRenderReport: String {
        if let metric = firstRenderMetric {
            return "\(metric.formattedDuration)s · \(metricResult(metric))"
        }
        return isMeasuringFirstRender ? "measuring…" : "not measured"
    }

    private func completeFirstRenderMeasurementIfNeeded(message: String, at date: Date) {
        guard let startedAt = firstRenderStartedAt else { return }

        if measurementKind == .firstUnread,
           message.hasPrefix("restored feed ") {
            restoredPostsDuringMeasurement = true
            return
        }

        let result: (postCount: Int, outcome: FirstRenderOutcome)?
        switch measurementKind {
        case .firstPosts:
            result = zeroToPostCount(in: message).map { ($0, .posts) }
        case .firstUnread:
            if let postCount = insertedNewerPostCount(in: message) {
                result = (postCount, .posts)
            }
            else if message == "initial newer pass finished · no new posts" {
                result = (0, .noNewPosts)
            }
            else if message == "initial newer pass timed out" {
                result = (0, .timedOut)
            }
            else if !restoredPostsDuringMeasurement,
                    let postCount = zeroToPostCount(in: message) {
                result = (postCount, .posts)
            }
            else {
                result = nil
            }
        }
        guard let result,
              result.outcome != .posts || result.postCount > 0
        else { return }

        firstRenderStartedAt = nil
        isMeasuringFirstRender = false
        firstRenderMetric = FirstRenderMetric(
            duration: max(0, date.timeIntervalSince(startedAt)),
            postCount: result.postCount,
            outcome: result.outcome
        )
    }

    private func zeroToPostCount(in message: String) -> Int? {
        guard let markerRange = message.range(of: "0→"),
              let postsRange = message.range(of: " posts", range: markerRange.upperBound..<message.endIndex)
        else { return nil }
        return Int(message[markerRange.upperBound..<postsRange.lowerBound])
    }

    private func insertedNewerPostCount(in message: String) -> Int? {
        let prefix = "inserted "
        let suffix = " newer at top"
        guard message.hasPrefix(prefix),
              let suffixRange = message.range(of: suffix)
        else { return nil }
        let countStart = message.index(message.startIndex, offsetBy: prefix.count)
        return Int(message[countStart..<suffixRange.lowerBound])
    }

    func metricCount(_ count: Int) -> String {
        measurementKind == .firstUnread ? "+\(count) posts" : "0→\(count)"
    }

    func metricResult(_ metric: FirstRenderMetric) -> String {
        switch metric.outcome {
        case .posts:
            metricCount(metric.postCount)
        case .noNewPosts:
            "NO NEW POSTS"
        case .timedOut:
            "CHECK TIMED OUT"
        }
    }

    var measurementTitle: String {
        measurementKind == .firstUnread ? "FIRST UNREAD" : "FIRST POSTS"
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        UserDefaults.standard.set(visible, forKey: Self.visibilityKey)
    }
}

struct FeedActionDebugOverlay: View {
    @ObservedObject var log: FeedActionDebugLog
    let feedName: String
    let currentState: () -> String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("FEED ACTIONS · \(feedName)")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(copied ? "Copied" : "Copy", action: copyReport)
                Button("Clear", action: log.clear)
                Button("Hide", action: log.hide)
            }

            firstRenderView

            Text("NOW  \(currentState())")
                .foregroundStyle(.cyan)
                .lineLimit(2)

            Divider().overlay(Color.white.opacity(0.25))

            if log.entries.isEmpty {
                Text("Waiting for feed activity…")
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text("newest first · \(log.entries.count)/60 kept")
                    .foregroundStyle(.white.opacity(0.45))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries.reversed()) { entry in
                            Text(entry.line)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .font(.caption2.monospaced())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.84))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var firstRenderView: some View {
        if let metric = log.firstRenderMetric {
            Text("\(log.measurementTitle)  \(metric.formattedDuration)s  ·  \(log.metricResult(metric))")
                .font(.headline.weight(.bold).monospaced())
                .foregroundStyle(color(for: metric.rating))
        } else if log.isMeasuringFirstRender {
            Text("\(log.measurementTitle)  MEASURING…")
                .font(.headline.weight(.bold).monospaced())
                .foregroundStyle(.white)
        } else {
            Text("\(log.measurementTitle)  NOT MEASURED")
                .font(.headline.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func color(for rating: FeedActionDebugLog.FirstRenderRating) -> Color {
        switch rating {
        case .fast: .green
        case .slow: .yellow
        case .failed: .red
        }
    }

    private func copyReport() {
        UIPasteboard.general.string = log.report(
            feedName: feedName,
            currentState: currentState()
        )
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copied = false
        }
    }
}
#endif
