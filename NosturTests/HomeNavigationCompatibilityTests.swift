import CoreData
import NavigationBackport
import SwiftUI
import XCTest
@testable import Nostur

@available(iOS 16.0, *)
@MainActor
final class HomeNavigationCompatibilityTests: XCTestCase {
    func testNativeHomeSupportsExistingBackportDestinations() async throws {
        try await verifyLocalDestinations(native: true)
    }

    func testLegacyHomeSupportsExistingBackportDestinations() async throws {
        try await verifyLocalDestinations(native: false)
    }

    func testNativeHomeOpensRegisteredWalletThroughEnvironmentNavigator() async throws {
        try await verifyWallet(native: true)
    }

    func testLegacyHomeOpensRegisteredWalletThroughEnvironmentNavigator() async throws {
        try await verifyWallet(native: false)
    }

    func testSheetFromNativeHomeSuppliesAppAndNavigationObjects() async throws {
        try await verifyModal(native: true, fullScreen: false)
    }

    func testSheetFromLegacyHomeSuppliesAppAndNavigationObjects() async throws {
        try await verifyModal(native: false, fullScreen: false)
    }

    func testFullScreenCoverFromNativeHomeSuppliesAppAndNavigationObjects() async throws {
        try await verifyModal(native: true, fullScreen: true)
    }

    func testFullScreenCoverFromLegacyHomeSuppliesAppAndNavigationObjects() async throws {
        try await verifyModal(native: false, fullScreen: true)
    }

    private func verifyLocalDestinations(native: Bool) async throws {
        let state = HomeCompatibilityState()
        let root = expectation(description: "Home root rendered")
        state.rootAppeared = { root.fulfill() }
        let window = try host(HomeCompatibilityHost(state: state, native: native))
        defer { window.isHidden = true }
        await fulfillment(of: [root], timeout: 5)
        XCTAssertNotNil(state.homeNavigator)
        try await openAndCloseLocalDestinations(state, in: window.rootViewController)
        XCTAssertEqual(state.path.count, 0)
    }

    private func verifyWallet(native: Bool) async throws {
        let state = HomeCompatibilityState()
        let root = expectation(description: "Home root rendered")
        state.rootAppeared = { root.fulfill() }
        let window = try host(HomeCompatibilityHost(state: state, native: native))
        defer { window.isHidden = true }
        await fulfillment(of: [root], timeout: 5)
        let navigator = try XCTUnwrap(state.homeNavigator)
        // Exercise the environment navigator and the production destination
        // registration, rather than mounting Wallet directly as a stack root.
        navigator.path.append(AnyHashable(ViewPath.Wallet))
        try await waitUntil { self.navigationTitle(in: window.rootViewController) == "Wallet" }
        XCTAssertEqual(state.path.count, 1)
        navigator.path.removeLast()
        try await waitUntil { self.navigationTitle(in: window.rootViewController) == "Home" }
        XCTAssertEqual(state.path.count, 0)
    }

    private func verifyModal(native: Bool, fullScreen: Bool) async throws {
        let state = HomeCompatibilityState()
        let modalState = HomeCompatibilityState()
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let entity = try XCTUnwrap(DataProvider.shared().container.managedObjectModel.entitiesByName["CloudAccount"])
        let account = CloudAccount(entity: entity, insertInto: context)
        account.publicKey = String(repeating: "a", count: 64)
        account.flagsSet = ["nostur_created"]
        let loggedInAccount = LoggedInAccount(account)
        let root = expectation(description: "Home root rendered")
        state.rootAppeared = { root.fulfill() }
        let window = try host(HomeCompatibilityHost(state: state, native: native,
                                                  account: loggedInAccount, fullScreen: fullScreen,
                                                  modalState: modalState))
        defer { window.isHidden = true }
        await fulfillment(of: [root], timeout: 5)
        let sheet = expectation(description: "Modal resolves app and navigation objects")
        modalState.modalAppeared = { actualAccount, navigator in
            XCTAssertTrue(actualAccount === loggedInAccount)
            XCTAssertFalse(navigator === state.homeNavigator)
            sheet.fulfill()
        }
        state.showModal = true
        await fulfillment(of: [sheet], timeout: 5)
        // onAppear fires before the modal presentation transition finishes.
        // Wait for a usable presentation before driving its navigation stack.
        try await waitUntil {
            guard let presented = window.rootViewController?.presentedViewController else { return false }
            return !presented.isBeingPresented && presented.transitionCoordinator == nil
        }
        try await openAndCloseLocalDestinations(modalState, in: window.rootViewController?.presentedViewController)
        XCTAssertEqual(state.path.count, 0, "Modal navigation must not push the underlying Home stack")
        state.showModal = false
        try await waitUntil { window.rootViewController?.presentedViewController == nil }
    }

    private func openAndCloseLocalDestinations(_ state: HomeCompatibilityState, in controller: UIViewController?) async throws {
        for usesItem in [false, true] {
            let appeared = expectation(description: "Existing backport destination opens")
            state.destinationAppeared = { appeared.fulfill() }
            if usesItem { state.item = "Comments" } else { state.showDestination = true }
            await fulfillment(of: [appeared], timeout: 5)
            try await waitUntil {
                self.navigationTitle(in: controller) == "Destination"
                    && self.navigationController(in: controller)?.transitionCoordinator == nil
            }
            if usesItem { state.item = nil } else { state.showDestination = false }
            try await waitUntil {
                self.navigationTitle(in: controller) == "Home"
                    && self.navigationController(in: controller)?.transitionCoordinator == nil
            }
        }
    }

    private func host<Content: View>(_ content: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        return window
    }

    private func navigationTitle(in controller: UIViewController?) -> String? {
        navigationController(in: controller)?.navigationBar.topItem?.title
    }

    private func navigationController(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        return controller.children.compactMap { navigationController(in: $0) }.first
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class HomeCompatibilityState: ObservableObject {
    @Published var path = NBNavigationPath()
    @Published var showDestination = false
    @Published var item: String?
    @Published var showModal = false
    var homeNavigator: PathNavigator?
    var rootAppeared: (() -> Void)?
    var modalAppeared: ((LoggedInAccount, PathNavigator) -> Void)?
    var destinationAppeared: (() -> Void)?
}

private struct HomeCompatibilityHost: View {
    @ObservedObject var state: HomeCompatibilityState
    let native: Bool
    var account: LoggedInAccount? = nil
    var fullScreen = false
    var modalState: HomeCompatibilityState? = nil

    var body: some View {
        HomeNavigationStack(path: $state.path, usesNativeNavigation: native) {
            HomeBackportControls(state: state)
        }
        .sheet(isPresented: Binding(get: { state.showModal && !fullScreen },
                                    set: { state.showModal = $0 })) { modal }
        .fullScreenCover(isPresented: Binding(get: { state.showModal && fullScreen },
                                              set: { state.showModal = $0 })) { modal }
    }

    @ViewBuilder private var modal: some View {
        if let account, let modalState {
            NRSheetNavigationStack {
                HomeModalEnvironmentProbe(state: modalState)
            }
            .environmentObject(account)
        }
    }
}

private struct HomeBackportControls: View {
    @EnvironmentObject private var navigator: PathNavigator
    @ObservedObject var state: HomeCompatibilityState
    var isModal = false

    var body: some View {
        VStack {
            Text("Home")
            // Keep direct backport controls here: the owning stack must remain
            // compatible with existing shared views, including ones not migrated.
            NBNavigationLink(value: ViewPath.Wallet) { Text("Wallet") }
        }
        .navigationTitle("Home")
        .nbNavigationDestination(isPresented: $state.showDestination) { destination }
        .nbNavigationDestination(item: $state.item) { _ in destination }
        .onAppear {
            guard !isModal else { return }
            state.homeNavigator = navigator
            let callback = state.rootAppeared
            state.rootAppeared = nil
            callback?()
        }
    }

    private var destination: some View {
        Text("Destination")
            .navigationTitle("Destination")
            .onAppear {
                let callback = state.destinationAppeared
                state.destinationAppeared = nil
                callback?()
            }
    }
}

private struct HomeModalEnvironmentProbe: View {
    @EnvironmentObject private var account: LoggedInAccount
    @EnvironmentObject private var navigator: PathNavigator
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var accounts: AccountsState
    @EnvironmentObject private var notifier: NewPostNotifier
    @EnvironmentObject private var messages: DMsVM
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var state: HomeCompatibilityState

    var body: some View {
        let _ = [app as AnyObject, accounts, notifier, messages, network, settings]
        HomeBackportControls(state: state, isModal: true)
            .onAppear {
                let callback = state.modalAppeared
                state.modalAppeared = nil
                callback?(account, navigator)
            }
    }
}
