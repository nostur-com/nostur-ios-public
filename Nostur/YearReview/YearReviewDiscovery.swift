import SwiftUI
import Combine

enum YearReviewDiscovery {
    static func seasonalYear(now: Date = .now, timeZone: TimeZone = .current) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 && day >= 18 { return year }
        if month == 1 && day <= 14 { return year - 1 }
        return nil
    }

    static func dismissalKey(owner: String, year: Int) -> String {
        "year-review-prompt-hidden-\(owner)-\(year)"
    }

    static func markOpened(owner: String, year: Int) {
        UserDefaults.standard.set(true, forKey: dismissalKey(owner: owner, year: year))
    }
}

@available(iOS 17.0, *)
struct YearReviewSeasonalPrompt: View {
    let owner: String
    let containerID: String
    @State private var now = Date.now

    var body: some View {
        if let year = YearReviewDiscovery.seasonalYear(now: now) {
            YearReviewSeasonalCard(owner: owner, year: year, containerID: containerID)
                .id(YearReviewDiscovery.dismissalKey(owner: owner, year: year))
        }
        // Refresh the seasonal window when returning to the app or crossing midnight.
        Color.clear.frame(height: 0)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))) { _ in now = .now }
            .onAppear { now = .now }
    }
}

@available(iOS 17.0, *)
@MainActor
private struct YearReviewSeasonalCard: View {
    @Environment(\.theme) private var theme
    @AppStorage private var hidden: Bool
    @State private var model = YearReviewModel.shared
    let owner: String
    let year: Int
    let containerID: String

    init(owner: String, year: Int, containerID: String) {
        self.owner = owner
        self.year = year
        self.containerID = containerID
        _hidden = AppStorage(wrappedValue: false, YearReviewDiscovery.dismissalKey(owner: owner, year: year))
    }

    var body: some View {
        if !hidden {
            HStack(spacing: 12) {
                Button {
                    hidden = true
                    navigateTo(YearReviewPath(year: year), context: containerID)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2).foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            if model.owner == owner && model.report?.period.year == year {
                                Text("Your Nostr year is ready").font(.subheadline.weight(.semibold))
                            } else {
                                Text("See your year on Nostr").font(.subheadline.weight(.semibold))
                            }
                            Text("Your people and highlights from \(String(year))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { hidden = true } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss year report reminder")
            }
            .padding(14)
            .background(theme.lineColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
