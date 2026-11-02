import CoreData
import NavigationBackport
import NostrEssentials
import SwiftUI
import XCTest
@testable import Nostur

@available(iOS 16.0, *)
@MainActor
final class ProfileNavigationTests: XCTestCase {
    func testNativeProfileDestinationsNeedNoBackportEnvironment() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            NavigationStack {
                ProfileNavigationProbe(state: state, usesNativeNavigation: true)
            }
        }
    }

    func testLegacyProfileDestinationsStillNavigate() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            NBNavigationStack {
                ProfileNavigationProbe(state: state, usesNativeNavigation: false)
            }
            .nbUseNavigationStack(.never)
        }
    }

    func testNativeBackportDetailDestinationsStillNavigate() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            NBNavigationStack {
                ProfileNavigationProbe(state: state, usesNativeNavigation: false)
            }
            .nbUseNavigationStack(.whenAvailable)
        }
    }

    func testNativeFeedLocalDestinationsNeedNoBackportEnvironment() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            NavigationStack {
                FeedLocalNavigationProbe(state: state)
                    .withNativeNavigationDestinations()
            }
        }
    }

    func testLegacyFeedLocalDestinationsStillNavigate() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            FeedLocalNavigationStack(state: state)
        }
    }

    func testLegacyStackOverridesNativeFeedDestinationEnvironment() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            FeedLocalNavigationStack(state: state)
                .environment(\.nativeLocalDestinations, true)
        }
    }

    func testActualVideoButtonAndPostFooterRenderUnderNativeNavigation() async throws {
        // NRPost's footer helpers use the app's importer context. Build the fixture
        // on that context, just as feed loading does, and pass only the view model.
        let context = bg()
        let eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let (post, objectID) = await context.perform {
            let event = Event.fromNEvent(nEvent: NEvent(
                id: eventID,
                publicKey: String(repeating: "e", count: 64),
                kind: .textNote,
                tags: []
            ), context: context)
            return (NRPost(event: event, withFooter: false, isPreview: true), event.objectID)
        }
        try await verifyRenders {
            NavigationStack {
                VStack {
                    VideoReplyButton(nrPost: post, theme: Themes.default.theme)
                    DetailFooterFragment(nrPost: post)
                }
                .environment(\.nxViewingContext, [.preview])
                .withNativeNavigationDestinations()
            }
        }
        await context.perform {
            if let event = context.registeredObject(for: objectID) { context.delete(event) }
        }
    }

    func testWalletRendersUnderNativeNavigationWithoutBackportObjects() async throws {
        try await verifyRenders {
            NavigationStack {
                WalletView().withNativeNavigationDestinations()
            }
        }
    }

    func testNativeValueLinkRendersWithoutBackportObjects() async throws {
        try await verifyRenders { ValueLinkNavigationProbe(native: true) }
    }

    func testLegacyValueLinkRendersWithInheritedNativeContext() async throws {
        try await verifyRenders { ValueLinkNavigationProbe(native: false) }
    }

    func testBackportContainerResetsInheritedNativeLocalDestinations() async throws {
        let state = ProfileNavigationProbeState()
        try await verifyDestinations(state: state) {
            NBNavigationStack {
                FeedLocalNavigationProbe(state: state)
            }
            .nosturNavigationStackCompat()
            .environment(\.nativeNavigationEnabled, false)
            .environment(\.nativeLocalDestinations, true)
        }
    }

    private func verifyRenders<Root: View>(@ViewBuilder root: () -> Root) async throws {
        let appeared = expectation(description: "Actual screen renders")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIHostingController(rootView: root().onAppear { appeared.fulfill() })
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [appeared], timeout: 5)
    }

    private func verifyDestinations<Root: View>(
        state: ProfileNavigationProbeState,
        @ViewBuilder root: () -> Root
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: root())
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = host
        let rootAppeared = expectation(description: "Profile root renders with both destinations registered")
        state.onRootAppear = { rootAppeared.fulfill() }
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [rootAppeared], timeout: 5)

        // The reported crash occurs when registering these two destinations,
        // before either binding becomes true. Also verify push and pop still work.
        for following in [true, false] {
            let appeared = expectation(description: following ? "Following opens" : "Followers opens")
            state.onDestinationAppear = { appeared.fulfill() }
            state.showFollowing = following
            state.showFollowers = !following
            await fulfillment(of: [appeared], timeout: 5)

            let disappeared = expectation(description: "List closes")
            state.onDestinationDisappear = { disappeared.fulfill() }
            state.showFollowing = false
            state.showFollowers = false
            await fulfillment(of: [disappeared], timeout: 5)
        }
    }
}

@MainActor
private final class ProfileNavigationProbeState: ObservableObject {
    @Published var showFollowing = false
    @Published var showFollowers = false
    var onRootAppear: (() -> Void)?
    var onDestinationAppear: (() -> Void)?
    var onDestinationDisappear: (() -> Void)?
}

private struct ProfileNavigationProbe: View {
    @ObservedObject var state: ProfileNavigationProbeState
    let usesNativeNavigation: Bool

    var body: some View {
        Text("Profile")
            .onAppear {
                let callback = state.onRootAppear
                state.onRootAppear = nil
                callback?()
            }
            .nosturNavigationDestination(isPresented: $state.showFollowing, usesNativeNavigation: usesNativeNavigation) {
                destination("Following")
            }
            .nosturNavigationDestination(isPresented: $state.showFollowers, usesNativeNavigation: usesNativeNavigation) {
                destination("Followers")
            }
    }

    private func destination(_ title: String) -> some View {
        Text(verbatim: title)
            .onAppear { state.onDestinationAppear?() }
            .onDisappear { state.onDestinationDisappear?() }
    }
}

// Exercise the item-based video-comments destination and the Boolean live-event
// destination while registering them in the same way as the feed's owning stack.
private struct FeedLocalNavigationProbe: View {
    @ObservedObject var state: ProfileNavigationProbeState

    var body: some View {
        Text("Feed")
            .onAppear {
                let callback = state.onRootAppear
                state.onRootAppear = nil
                callback?()
            }
            .nosturNavigationDestination(item: Binding<String?>(
                get: { state.showFollowing ? "Comments" : nil },
                set: { state.showFollowing = $0 != nil }
            )) { title in
                destination(title)
            }
            .nosturNavigationDestination(isPresented: $state.showFollowers) {
                destination("Zap")
            }
    }

    private func destination(_ title: String) -> some View {
        Text(verbatim: title)
            .onAppear { state.onDestinationAppear?() }
            .onDisappear { state.onDestinationDisappear?() }
    }
}

private struct FeedLocalNavigationStack: View {
    @ObservedObject var state: ProfileNavigationProbeState
    @State private var path = NBNavigationPath()

    var body: some View {
        NBNavigationStack(path: $path) {
            FeedLocalNavigationProbe(state: state)
                .withNavigationDestinations(navPath: $path)
        }
        .nbUseNavigationStack(.never)
    }
}

@available(iOS 16.0, *)
private struct ValueLinkNavigationProbe: View {
    let native: Bool

    var body: some View {
        if native {
            NavigationStack {
                link
                    .navigationDestination(for: String.self) { _ in destination }
                    .environment(\.nativeLocalDestinations, true)
            }
        } else {
            NBNavigationStack {
                link.nbNavigationDestination(for: String.self) { _ in destination }
            }
            .nosturNavigationStackCompat()
            .environment(\.nativeNavigationEnabled, false)
            .environment(\.nativeLocalDestinations, true)
        }
    }

    private var link: some View {
        NosturNavigationLink(value: "Destination") { Text("Open") }
            .accessibilityIdentifier("navigation-audit-link")
    }

    private var destination: some View {
        Text("Destination")
    }
}
