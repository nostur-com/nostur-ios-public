import SwiftUI
import Combine

enum YearReviewFeature {
    static let earlyAccessKey = "year-review-early-access"

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        isAvailableInRelease()
        #endif
    }

    static func isAvailableInRelease(now: Date = .now, timeZone: TimeZone = .current,
                                    defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: earlyAccessKey) || isReleased(now: now, timeZone: timeZone)
    }

    // Release access begins after December 10 in the device's local time.
    static func isReleased(now: Date = .now, timeZone: TimeZone = .current) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let launch = calendar.date(from: DateComponents(year: 2026, month: 12, day: 11)) else { return false }
        return now >= launch
    }
}

@MainActor
final class YearReviewEarlyAccess: ObservableObject {
    static let shared = YearReviewEarlyAccess()
    @Published private(set) var isUnlocked: Bool
    private var taps = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isUnlocked = defaults.bool(forKey: YearReviewFeature.earlyAccessKey)
    }

    func tapVersion() {
        guard !isUnlocked else { return }
        taps += 1
        guard taps == 9 else { return }
        defaults.set(true, forKey: YearReviewFeature.earlyAccessKey)
        isUnlocked = true
    }
}

enum YearReviewDiscovery {
    static func seasonalYear(now: Date = .now, timeZone: TimeZone = .current) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 && day >= 11 { return year }
        if month == 1 && day <= 14 { return year - 1 }
        return nil
    }

    static func dismissalKey(owner: String, year: Int) -> String {
        "year-review-prompt-hidden-\(owner)-\(year)"
    }

    @MainActor
    static func markOpened(owner: String, year: Int) {
        YearReviewDiscoveryState.shared.markOpened(owner: owner, year: year)
    }

    static func promptYear(now: Date = .now) -> Int? {
        #if DEBUG
        YearReviewPeriod.defaultYear(now: now)
        #else
        YearReviewFeature.isReleased(now: now) ? seasonalYear(now: now) : nil
        #endif
    }

    static func canPresent(isVisible: Bool, isAtTop: Bool, unreadCount: Int, isRestoring: Bool) -> Bool {
        isVisible && isAtTop && unreadCount == 0 && !isRestoring
    }
}

/// DEBUG keeps discovery state in memory so opening or snoozing still works,
/// but every fresh process gets another chance to test it.
@MainActor
final class YearReviewDiscoveryState: ObservableObject {
    static let shared = YearReviewDiscoveryState()
    @Published private var revision = 0
    private let defaults: UserDefaults
    private let resetsOnLaunch: Bool
    private var openedThisLaunch: Set<String> = []
    private var deferredThisLaunch: [String: Date] = [:]

    init(defaults: UserDefaults = .standard, resetsOnLaunch: Bool = _isDebugAssertConfiguration()) {
        self.defaults = defaults
        self.resetsOnLaunch = resetsOnLaunch
    }

    func hasOpened(owner: String, year: Int) -> Bool {
        let key = YearReviewDiscovery.dismissalKey(owner: owner, year: year)
        return resetsOnLaunch ? openedThisLaunch.contains(owner) :
            defaults.bool(forKey: "year-review-opened-\(owner)") || defaults.bool(forKey: key)
    }

    func shouldPrompt(owner: String, year: Int, now: Date = .now) -> Bool {
        guard !hasOpened(owner: owner, year: year) else { return false }
        let key = YearReviewDiscovery.dismissalKey(owner: owner, year: year) + "-later"
        let until = resetsOnLaunch ? deferredThisLaunch[key] : defaults.object(forKey: key) as? Date
        return until.map { now >= $0 } ?? true
    }

    func markOpened(owner: String, year: Int) {
        let key = YearReviewDiscovery.dismissalKey(owner: owner, year: year)
        if resetsOnLaunch { openedThisLaunch.insert(owner) }
        else {
            defaults.set(true, forKey: "year-review-opened-\(owner)")
            defaults.set(true, forKey: key)
        }
        revision += 1
    }

    func remindLater(owner: String, year: Int, now: Date = .now, calendar: Calendar = .current) {
        let key = YearReviewDiscovery.dismissalKey(owner: owner, year: year) + "-later"
        let until = calendar.date(byAdding: .day, value: 3, to: now) ?? now.addingTimeInterval(3 * 86_400)
        if resetsOnLaunch { deferredThisLaunch[key] = until }
        else { defaults.set(until, forKey: key) }
        revision += 1
    }
}

@available(iOS 17.0, *)
@MainActor
struct YearReviewSeasonalPrompt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let owner: String
    let containerID: String
    let feedState: NXColumnViewModelInner
    let isVisible: Bool
    @ObservedObject private var discovery = YearReviewDiscoveryState.shared
    @ObservedObject private var unreadState: NXColumnUnreadState
    @State private var now = Date.now
    @State private var isAtTop = false
    @State private var displayedYear: Int? = nil

    private var eligibleYear: Int? {
        guard let year = YearReviewDiscovery.promptYear(now: now),
              YearReviewDiscovery.canPresent(isVisible: isVisible, isAtTop: isAtTop,
                  unreadCount: unreadState.unreadCount, isRestoring: feedState.isPreparingForScrollRestore),
              discovery.shouldPrompt(owner: owner, year: year, now: now) else { return nil }
        return year
    }

    init(owner: String, containerID: String, feedState: NXColumnViewModelInner, isVisible: Bool) {
        self.owner = owner
        self.containerID = containerID
        self.feedState = feedState
        self.isVisible = isVisible
        self.unreadState = feedState.unreadState
    }

    var body: some View {
        VStack(spacing: 0) {
            if let year = displayedYear {
                YearReviewSeasonalCard(owner: owner, year: year, containerID: containerID)
                    .transition(.opacity)
            }
        }
        .onChange(of: eligibleYear, initial: true) { _, year in
            let animation: Animation? = isVisible && !reduceMotion ? .easeInOut(duration: 0.25) : nil
            withAnimation(animation) { displayedYear = year }
        }
        .onReceive(feedState.isAtTopPublisher.removeDuplicates().receive(on: DispatchQueue.main)) { isAtTop = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))) { _ in now = .now }
        .onAppear { now = .now }
        .onChange(of: isVisible) { _, visible in
            if visible { now = .now }
        }
    }
}

@available(iOS 17.0, *)
@MainActor
private struct YearReviewSeasonalCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var discovery = YearReviewDiscoveryState.shared
    let owner: String
    let year: Int
    let containerID: String

    var body: some View {
        HStack(spacing: 12) {
            Button {
                discovery.markOpened(owner: owner, year: year)
                navigateTo(YearReviewPath(year: year), context: containerID)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("See your year on Nostr").font(.subheadline.weight(.semibold))
                        Text("Your people and highlights from \(String(year))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                discovery.remindLater(owner: owner, year: year)
            } label: {
                Text("Later", comment: "Hide the Year in Review feed reminder for three days")
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .padding(.vertical, 12)
        }
        .padding(14)
        .background(theme.lineColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One brief greeting per drawer opening. Overlays keep the menu's typography,
/// hit target and row size unchanged throughout the animation.
@MainActor
struct YearReviewSidebarLabel: View {
    @Environment(\.theme) private var theme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var discovery = YearReviewDiscoveryState.shared
    let owner: String
    let isSidebarVisible: Bool
    @State private var glowing = false
    @State private var twinkling = false
    @State private var shine: CGFloat = 0
    @State private var sparkle = 0

    private var shouldAnimate: Bool {
        isSidebarVisible && !reduceMotion &&
            !discovery.hasOpened(owner: owner, year: YearReviewPeriod.defaultYear())
    }

    private var title: Text {
        Text("Your year on Nostr", comment: "Side bar navigation button")
    }

    var body: some View {
        Label {
            title
                .foregroundColor(glowing ? theme.primary : theme.accent)
                .overlay {
                    GeometryReader { geometry in
                        let bandWidth = max(28, geometry.size.width * 0.4)
                        let travel = geometry.size.width + bandWidth * 2
                        let progress = layoutDirection == .rightToLeft ? 1 - shine : shine
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: theme.accent, location: 0.3),
                            .init(color: .white, location: 0.5),
                            .init(color: theme.accent, location: 0.7),
                            .init(color: .clear, location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                        .frame(width: bandWidth, height: geometry.size.height * 2)
                        .rotationEffect(.degrees(-18))
                        .offset(x: travel * progress - bandWidth * 1.5,
                            y: -geometry.size.height / 2)
                    }
                    .mask(title)
                    .opacity(glowing ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(width: SideBar.MENU_TEXT_WIDTH, alignment: .leading)
        } icon: {
            icon
                .scaleEffect(glowing ? 1.18 : 1)
                .foregroundColor(glowing ? theme.primary : theme.accent)
                .shadow(color: theme.accent.opacity(glowing ? 0.55 : 0), radius: 5)
                .overlay(alignment: .topTrailing) {
                    glint(size: 9, rotation: 25)
                        .offset(x: 5, y: -5)
                }
                .overlay(alignment: .bottomLeading) {
                    glint(size: 6, rotation: -30)
                        .offset(x: -5, y: 4)
                }
                .frame(width: SideBar.ICON_WIDTH)
        }
        .task(id: shouldAnimate) {
            resetAnimation()
            guard shouldAnimate else { return }
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                sparkle += 1
                withAnimation(.easeInOut(duration: 0.45)) { glowing = true }
                withAnimation(.easeOut(duration: 0.35)) { twinkling = true }
                withAnimation(.linear(duration: 1.15)) { shine = 1 }
                try await Task.sleep(nanoseconds: 650_000_000)
                try Task.checkCancellation()
                withAnimation(.easeIn(duration: 0.45)) { twinkling = false }
                try await Task.sleep(nanoseconds: 650_000_000)
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.65)) { glowing = false }
            } catch { resetAnimation() }
        }
    }

    private func resetAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            glowing = false
            twinkling = false
            shine = 0
        }
    }

    private func glint(size: CGFloat, rotation: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(theme.accent)
            .scaleEffect(twinkling ? 1 : 0.2)
            .rotationEffect(.degrees(twinkling ? rotation : -rotation))
            .opacity(twinkling ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "sparkles")
                .symbolEffect(.bounce.byLayer, options: .nonRepeating, value: sparkle)
        } else {
            Image(systemName: "sparkles")
                .rotationEffect(.degrees(glowing ? 10 : 0))
        }
    }
}
