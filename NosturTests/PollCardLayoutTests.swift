import SwiftUI
import XCTest
@testable import Nostur

@MainActor
final class PollCardLayoutTests: XCTestCase {
    func testResultsSheetOverviewAndFocusedAnswerRender() async throws {
        let now = Int(Date().timeIntervalSince1970)
        let poll = NostrPoll(id: String(repeating: "aa", count: 32), createdAt: now - 3600,
                             tags: [["option", "a", "Widespread Bitcoin adoption"],
                                    ["option", "b", "The year of the Linux desktop"],
                                    ["endsAt", String(now - 10)]])
        let votes = (1...6).map { number in
            PollVote(id: String(number), pubkey: String(format: "%064x", number),
                     createdAt: now - 600 - number * 60, responses: [number == 1 ? "a" : "b"])
        }
        let model = PollViewModel(poll: poll, initialVotes: votes)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for selected in [String?.none, Optional("b")] {
            let host = UIHostingController(rootView: PollVotersSheet(model: model, selectedOption: selected)
                .environment(\.theme, Themes.default.theme)
                .environment(\.colorScheme, .light))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(nanoseconds: 250_000_000)
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let name = selected == nil ? "poll-results-overview" : "poll-results-answer"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("POLL_SHEET_RENDER: \(url.path)")
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
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
