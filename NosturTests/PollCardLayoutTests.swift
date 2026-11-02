import SwiftUI
import NavigationBackport
import XCTest
@testable import Nostur

@MainActor
final class PollCardLayoutTests: XCTestCase {
    func testAllResultsSegmentsCanBeSelected() async throws {
        let now = Int(Date().timeIntervalSince1970)
        let poll = NostrPoll(id: String(repeating: "aa", count: 32), createdAt: now - 60,
                             tags: [["option", "a", "First"], ["option", "b", "Second"]])
        let model = PollViewModel(poll: poll, initialVotes: [
            PollVote(id: "1", pubkey: String(repeating: "ab", count: 32), createdAt: now - 10, responses: ["b"])])
        let host = UIHostingController(rootView: PollVotersSheet(model: model, selectedOption: "b", dismissSheet: {}))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 250_000_000)
        var bodyImages: [Int: Data] = [:]
        for index in [2, 1, 0] {
            let control = try XCTUnwrap(descendant(UISegmentedControl.self, in: host.view))
            XCTAssertTrue(control.isEnabledForSegment(at: index))
            let point = control.convert(CGPoint(x: control.bounds.width * (CGFloat(index) + 0.5) / 3,
                                                y: control.bounds.midY), to: host.view)
            let hit = host.view.hitTest(point, with: nil)
            XCTAssertTrue(hit === control || hit?.isDescendant(of: control) == true,
                          "Segment \(index) is covered by \(String(describing: hit))")
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            try await Task.sleep(nanoseconds: 100_000_000)
            let updated = try XCTUnwrap(descendant(UISegmentedControl.self, in: host.view))
            XCTAssertEqual(updated.selectedSegmentIndex, index)
            let top = updated.convert(updated.bounds, to: host.view).maxY + 8
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 250), format: format).image { context in
                context.cgContext.translateBy(x: 0, y: -top)
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            bodyImages[index] = try XCTUnwrap(image.pngData())
            let attachment = XCTAttachment(image: image)
            attachment.name = "scope-content-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)

        }
        XCTAssertNotEqual(bodyImages[1], bodyImages[2], "Web of Trust must update the answer content, not only the picker highlight")
        XCTAssertNotEqual(bodyImages[0], bodyImages[2], "Everyone must restore the answer results")
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    func testScopedResultsFilterCountsAndAnswerListsTogether() {
        let poll = NostrPoll(id: String(repeating: "ab", count: 32), createdAt: 100,
                             tags: [["polltype", "multiplechoice"], ["option", "a", "First"],
                                    ["option", "b", "Second"]])
        let votes = [PollVote(id: "1", pubkey: "followed", createdAt: 101, responses: ["a", "b"]),
                     PollVote(id: "2", pubkey: "trusted", createdAt: 102, responses: ["b"]),
                     PollVote(id: "3", pubkey: "stranger", createdAt: 103, responses: ["a"])]
        let everyone = PollTally(poll: poll, votes: votes, now: 200)
        let trusted = everyone.filtered(to: ["followed", "trusted"])
        XCTAssertEqual(trusted.totalVoters, 2)
        XCTAssertEqual(trusted.voters(for: "a").map(\.pubkey), ["followed"])
        XCTAssertEqual(trusted.voters(for: "b").count, 2)
        XCTAssertEqual(Double(trusted.voters(for: "a").count) / Double(trusted.totalVoters), 0.5)
        let followed = everyone.filtered(to: ["followed"])
        XCTAssertEqual(followed.totalVoters, 1)
        XCTAssertEqual(followed.voters(for: "a").count, 1)
        XCTAssertEqual(followed.voters(for: "b").count, 1)
        XCTAssertEqual(everyone.totalVoters, 3, "Filtering must preserve the unfiltered results")
        let empty = everyone.filtered(to: [])
        XCTAssertEqual(empty.totalVoters, 0)
        XCTAssertTrue(empty.voters(for: "a").isEmpty)
        XCTAssertTrue(empty.voters(for: nil).isEmpty)
    }

    func testAnswerVoterFilterNeverFallsBackToEveryone() {
        let poll = NostrPoll(id: String(repeating: "ab", count: 32), createdAt: 100,
                             tags: [["option", "a", "First"], ["option", "b", "Second"],
                                    ["option", "c", "No votes"]])
        let first = PollVote(id: "1", pubkey: "first", createdAt: 101, responses: ["a"])
        let second = PollVote(id: "2", pubkey: "second", createdAt: 102, responses: ["b"])
        let tally = PollTally(poll: poll, votes: [first, second], now: 200)
        XCTAssertEqual(tally.voters(for: nil).count, 2)
        XCTAssertEqual(tally.voters(for: "a").map(\.pubkey), ["first"])
        XCTAssertEqual(tally.voters(for: "b").map(\.pubkey), ["second"])
        XCTAssertTrue(tally.voters(for: "c").isEmpty)
        XCTAssertTrue(tally.voters(for: "unknown").isEmpty)
    }

    func testResultsSourcesCollapsedAndExpandedRender() async throws {
        let now = Int(Date().timeIntervalSince1970)
        let poll = NostrPoll(id: String(repeating: "ab", count: 32), createdAt: now - 60,
                             tags: [["option", "a", "First"], ["option", "b", "Second"]])
        let checked = Date(timeIntervalSince1970: TimeInterval(now - 60))
        let sources = [PollResultsSource(id: "wss://relay.damus.io", status: .checked, lastChecked: checked),
                       PollResultsSource(id: "wss://filter.nostr.wine", status: .failed, lastChecked: checked,
                                         failure: PollRelayFailure(.authenticationRequired, detail: "auth-required: please authenticate before sending REQs")),
                       PollResultsSource(id: "wss://relay.primal.net", status: .pending),
                       PollResultsSource(id: "wss://relay.example.com", status: .moreAvailable, lastChecked: checked)]
        let model = PollViewModel(poll: poll, initialVotes: [], initialSources: sources)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for expanded in [false, true] {
            let host = UIHostingController(rootView: ScrollView {
                PollResultsSourcesView(model: model, expanded: expanded).padding(16)
            }.environment(\.theme, Themes.default.theme).environment(\.colorScheme, .light))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(nanoseconds: 200_000_000)
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = expanded ? "poll-sources-expanded" : "poll-sources-collapsed"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testResultsSheetOverviewAndFocusedAnswerRender() async throws {
        let now = Int(Date().timeIntervalSince1970)
        let poll = NostrPoll(id: String(repeating: "aa", count: 32), createdAt: now - 3600,
                             tags: [["option", "a", "Widespread Bitcoin adoption"],
                                    ["option", "b", "The year of the Linux desktop"],
                                    ["endsAt", String(now - 10)]])
        let votes = (1...19).map { number in
            PollVote(id: String(number), pubkey: String(format: "%064x", number),
                     createdAt: now - 600 - number * 60, responses: [number == 1 ? "a" : "b"])
        }
        let checked = Date(timeIntervalSince1970: TimeInterval(now - 60))
        let sources = (1...6).map { PollResultsSource(id: "wss://relay\($0).example", status: .checked, lastChecked: checked) }
            + [PollResultsSource(id: "wss://filter.nostr.wine", status: .failed, lastChecked: checked,
                                 failure: PollRelayFailure(.authenticationRequired, detail: "auth-required: please authenticate before sending REQs"))]
        let model = PollViewModel(poll: poll, initialVotes: votes, initialSources: sources)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for width in [390.0, 620.0] {
            for selected in [String?.none, Optional("b")] {
                let host = UIHostingController(rootView: PollVotersSheet(model: model, selectedOption: selected, dismissSheet: {})
                    .environment(\.theme, Themes.default.theme)
                    .environment(\.colorScheme, .light)
                    .nbUseNavigationStack(.never))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                try await Task.sleep(nanoseconds: 250_000_000)
                window.layoutIfNeeded()
                XCTAssertEqual(visibleNavigationBars(in: host.view), 1,
                               "Poll results must have one navigation bar even when opened from a legacy feed stack")
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let name = (selected == nil ? "poll-results-overview" : "poll-results-answer") + "-\(Int(width))"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
                try XCTUnwrap(image.pngData()).write(to: url)
                print("POLL_SHEET_RENDER: \(url.path)")
                let attachment = XCTAttachment(image: image)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func visibleNavigationBars(in view: UIView) -> Int {
        guard !view.isHidden, view.alpha > 0 else { return 0 }
        return (view is UINavigationBar ? 1 : 0)
            + view.subviews.reduce(0) { $0 + visibleNavigationBars(in: $1) }
    }

    func testBookmarkListAndSearchScrollViewHaveMatchingPollHeights() async throws {
        let scrollHeight = try await renderedHeight(inList: false)
        let listHeight = try await renderedHeight(inList: true)
        XCTAssertGreaterThan(scrollHeight, 100)
        XCTAssertGreaterThan(listHeight, 100)
        XCTAssertEqual(listHeight, scrollHeight, accuracy: 2,
                       "List stretched the poll: \(listHeight), compared with ScrollView: \(scrollHeight)")
    }

    private func renderedHeight(inList: Bool) async throws -> CGFloat {
        let poll = NostrPoll(id: String(repeating: inList ? "cd" : "ef", count: 32), createdAt: 100,
                             tags: [["option", "a", "Widespread Bitcoin adoption"],
                                    ["option", "b", "The year of the Linux desktop"], ["endsAt", "200"]])
        let probe = PollHeightProbe()
        let card = PollCard(poll: poll)
            .environment(\.nxViewingContext, [.preview])
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { probe.height = geometry.size.height }
                        .onChange(of: geometry.size) { size in probe.height = size.height }
                }
            }
        let root = inList
            ? AnyView(List { card.listRowInsets(EdgeInsets()) }.listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 50))
            : AnyView(ScrollView { card })
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 200_000_000)
        window.layoutIfNeeded()
        return probe.height
    }

    func testEndedPollKeepsContentHeightUnderTallRowProposals() throws {
        if #available(iOS 16.0, *) {
            let poll = NostrPoll(id: String(repeating: "ab", count: 32), createdAt: 100,
                                 tags: [["option", "a", "Widespread Bitcoin adoption"],
                                        ["option", "b", "The year of the Linux desktop"], ["endsAt", "200"]])
            let host = UIHostingController(rootView: PollCard(poll: poll)
                .environment(\.nxViewingContext, [.preview]))
            for width in [320.0, 390.0] {
                let compact = host.sizeThatFits(in: CGSize(width: width, height: 600))
                let tall = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                XCTAssertLessThan(tall.height, 400, "A two-option poll must not fill its proposed row height")
                XCTAssertEqual(compact.height, tall.height, accuracy: 1,
                               "Bookmark List and search ScrollView proposals must keep the same content height")
            }
        }
    }
}

@MainActor
private final class PollHeightProbe {
    var height: CGFloat = 0
}
