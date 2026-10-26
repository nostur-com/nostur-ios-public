import NavigationBackport
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
