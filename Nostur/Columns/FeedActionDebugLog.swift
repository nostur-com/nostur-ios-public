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
    private static let maximumEntries = 10

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isVisible: Bool

    init() {
        if UserDefaults.standard.object(forKey: Self.visibilityKey) == nil {
            isVisible = true
        } else {
            isVisible = UserDefaults.standard.bool(forKey: Self.visibilityKey)
        }
    }

    func record(_ message: String) {
        entries.append(Entry(date: Date(), message: message))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
    }

    func show() {
        setVisible(true)
    }

    func hide() {
        setVisible(false)
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    func report(feedName: String, currentState: String) -> String {
        let actionLines = entries.isEmpty
            ? "(no feed actions recorded yet)"
            : entries.map(\.line).joined(separator: "\n")
        return """
        Feed action log: \(feedName)
        Current: \(currentState)
        Last \(entries.count) actions:
        \(actionLines)
        """
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

            Text("NOW  \(currentState())")
                .foregroundStyle(.cyan)
                .lineLimit(2)

            Divider().overlay(Color.white.opacity(0.25))

            if log.entries.isEmpty {
                Text("Waiting for feed activity…")
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries) { entry in
                        Text(entry.line)
                            .lineLimit(1)
                    }
                }
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
