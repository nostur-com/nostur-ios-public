import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class NosturProLayoutTests: XCTestCase {
    @available(iOS 17.0, *)
    func testRenderedShellFollowsRepeatedFoldUnfoldWithoutRetogglingPro() async throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Adaptive phone shell requires iOS 27.1") }
        try XCTSkipUnless(IS_IPHONE, "Phone layout regression")
        let suite = "NosturProRenderedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.proMode = true
        var onShellAppear: ((Bool) -> Void)?
        let host = UIHostingController(rootView: NosturProLayout(settings: settings) {
            Text("Pro columns").onAppear { onShellAppear?(true) }
        } normalContent: {
            Text("Original phone shell").onAppear { onShellAppear?(false) }
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        host.traitOverrides.horizontalSizeClass = .compact
        let initial = expectation(description: "Folded launch uses the original shell")
        onShellAppear = { if !$0 { initial.fulfill() } }
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [initial], timeout: 5)

        // Reuse the same controller and settings, just as a live pose change does.
        for expanded in [true, false, true, false, true, false] {
            let appeared = expectation(description: expanded ? "Unfold restores Pro" : "Fold restores original phone")
            onShellAppear = { if $0 == expanded { appeared.fulfill() } }
            host.traitOverrides.horizontalSizeClass = expanded ? .regular : .compact
            window.layoutIfNeeded()
            await fulfillment(of: [appeared], timeout: 5)
            XCTAssertEqual(settings.usesProColumns, expanded)
            XCTAssertTrue(settings.proMode)
        }
    }

    @available(iOS 17.0, *)
    func testProSidebarFollowsChangingAsymmetricSafeAreas() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var markerFrame = CGRect.zero
        var columnsFrame = CGRect.zero
        var onMarkerLayout: (() -> Void)?
        let host = UIHostingController(rootView: ProSidebarLayout {
            VStack {
                Color.red.frame(width: 30, height: 30)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        markerFrame = frame
                        onMarkerLayout?()
                    }
                Spacer()
            }
            .frame(width: SIDEBAR_WIDTH)
        } columns: {
            Color.blue
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { columnsFrame = $0 }
        })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for insets in [UIEdgeInsets(top: 90, left: 70, bottom: 20, right: 0),
                       UIEdgeInsets(top: 30, left: 0, bottom: 30, right: 110)] {
            let laidOut = expectation(description: "Sidebar follows current safe area")
            onMarkerLayout = {
                onMarkerLayout = nil
                laidOut.fulfill()
            }
            host.additionalSafeAreaInsets = insets
            window.layoutIfNeeded()
            await fulfillment(of: [laidOut], timeout: 5)
            onMarkerLayout = nil
            let safeFrame = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: window)
            XCTAssertTrue(safeFrame.insetBy(dx: -0.5, dy: -0.5).contains(markerFrame),
                          "Top account control must stay within the live safe area: \(markerFrame), safe \(safeFrame)")
            XCTAssertGreaterThanOrEqual(columnsFrame.minX, markerFrame.maxX)
            XCTAssertLessThanOrEqual(columnsFrame.maxX, safeFrame.maxX + 0.5)
            XCTAssertGreaterThanOrEqual(columnsFrame.maxX, safeFrame.maxX - 1.5,
                                       "Columns must fill the usable width, without an extra trailing gap")
        }
    }

    @available(iOS 26.0, *)
    func testSidebarAccountControlClearsTheActualDisplayCorner() async throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Pro columns on iPhone require iOS 27.1") }
        try XCTSkipUnless(IS_IPHONE, "Phone corner regression")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var markerFrame = CGRect.zero
        var columnsFrame = CGRect.zero
        var onMarkerLayout: (() -> Void)?
        let host = UIHostingController(rootView: ProSidebarLayout {
            VStack {
                Color.red.frame(width: 30, height: 30)
                    .padding(10)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        markerFrame = frame.insetBy(dx: 10, dy: 10)
                        onMarkerLayout?()
                    }
                Spacer()
            }
            .frame(width: SIDEBAR_WIDTH)
        } columns: {
            Color.blue
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { columnsFrame = $0 }
        })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        let cornerCleared = expectation(description: "Account control clears the rounded corner")
        onMarkerLayout = {
            guard let probe = self.cornerProbe(in: host.view) else { return }
            let region = probe.directionalEdgeInsets(for: .safeArea(cornerAdaptation: .vertical))
            let cornerTop = probe.convert(CGPoint(x: 0, y: region.top), to: window).y
            if markerFrame.minY >= cornerTop + 9.5 {
                onMarkerLayout = nil
                cornerCleared.fulfill()
            }
        }
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [cornerCleared], timeout: 5)
        window.layoutIfNeeded()
        let probe = try XCTUnwrap(cornerProbe(in: host.view))
        let region = probe.directionalEdgeInsets(for: .safeArea(cornerAdaptation: .vertical))
        let cornerTop = probe.convert(CGPoint(x: 0, y: region.top), to: window).y
        XCTAssertGreaterThanOrEqual(markerFrame.minY, cornerTop + 9.5)
        let safeFrame = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: window)
        XCTAssertEqual(columnsFrame.maxX, safeFrame.maxX, accuracy: 1.5)
        let attachment = XCTAttachment(string: "Window: \(window.bounds); safe frame: \(safeFrame); columns: \(columnsFrame); sidebar corner region: \(region); account frame: \(markerFrame)")
        attachment.name = "Duo usable width and corner clearance"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @available(iOS 26.0, *)
    private func cornerProbe(in view: UIView) -> ProSidebarCornerRegionView? {
        if let probe = view as? ProSidebarCornerRegionView { return probe }
        return view.subviews.lazy.compactMap { self.cornerProbe(in: $0) }.first
    }

    func testFirstPhoneSetupSeedsNotificationsAndPreservesSavedColumns() throws {
        let suite = "NosturProColumnsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = MacColumnsVM(defaults: defaults)
        let pubkey = String(repeating: "a", count: 64)
        vm.restoreConfiguredColumns(defaultPhoneAccount: pubkey)
        XCTAssertEqual(vm.columns.count, 1, "Following plus notifications makes two total columns")
        if case .notifications(let accountPubkey) = vm.columns.first?.type {
            XCTAssertEqual(accountPubkey, pubkey)
        }
        else { XCTFail("Default column should be current-account notifications") }
        let initialColumns = vm.columns
        vm.restoreConfiguredColumns(defaultPhoneAccount: pubkey)
        XCTAssertEqual(vm.columns, initialColumns, "Reopening must not replace configured columns")

        vm.columns.append(MacColumnConfig(type: .emoji))
        vm.saveState()
        let savedColumns = vm.columns
        vm.restoreConfiguredColumns(defaultPhoneAccount: pubkey)
        XCTAssertEqual(vm.columns, savedColumns)

        vm.columns = []
        vm.saveState()
        vm.restoreConfiguredColumns(defaultPhoneAccount: pubkey)
        XCTAssertTrue(vm.columns.isEmpty, "An intentionally removed column must not reappear")

        defaults.removeObject(forKey: "mac_columns_serialized")
        let macVM = MacColumnsVM(defaults: defaults)
        macVM.restoreConfiguredColumns(defaultPhoneAccount: nil)
        XCTAssertTrue(macVM.columns.isEmpty, "Keep the existing Catalyst default")
    }

    func testFoldUnfoldKeepsPreferenceButOnlyActivatesExpandedColumns() throws {
        try XCTSkipIf(IS_CATALYST, "Phone layout regression")
        let settings = SettingsStore.shared
        let originalTab = UserDefaults.standard.object(forKey: "selected_tab")
        let originalNotificationsTab = UserDefaults.standard.object(forKey: "selected_notifications_tab")
        let originalVMTab = MacColumnsVM.shared.selectedTab
        let originalVMNotificationsTab = MacColumnsVM.shared.selectedNotificationsTab
        let originalProMode = settings.proMode
        let originalProPreference = UserDefaults.standard.object(forKey: SettingsStore.Keys.proMode)
        let originalExpanded = settings.phoneIsExpanded
        defer {
            MacColumnsVM.shared.selectedTab = originalVMTab
            MacColumnsVM.shared.selectedNotificationsTab = originalVMNotificationsTab
            UserDefaults.standard.set(originalTab, forKey: "selected_tab")
            UserDefaults.standard.set(originalNotificationsTab, forKey: "selected_notifications_tab")
            settings.proMode = originalProMode
            settings.updatePhoneLayout(isExpanded: originalExpanded)
            if originalProPreference == nil {
                UserDefaults.standard.removeObject(forKey: SettingsStore.Keys.proMode)
            }
        }

        settings.proMode = true
        settings.updatePhoneLayout(isExpanded: false)
        XCTAssertFalse(IS_DESKTOP_COLUMNS())

        settings.updatePhoneLayout(isExpanded: true)
        XCTAssertTrue(IS_DESKTOP_COLUMNS())
        setSelectedTab("Search")
        XCTAssertEqual(MacColumnsVM.shared.selectedTab, "Search")
        setSelectedNotificationsTab("Reactions")
        XCTAssertEqual(MacColumnsVM.shared.selectedNotificationsTab, "Reactions")

        settings.updatePhoneLayout(isExpanded: false)
        XCTAssertFalse(IS_DESKTOP_COLUMNS())
        XCTAssertTrue(settings.proMode, "Folding must not turn off the saved preference")
        XCTAssertTrue(settings.phoneHasExpanded, "The toggle must remain available after folding")

        settings.updatePhoneLayout(isExpanded: true)
        XCTAssertTrue(IS_DESKTOP_COLUMNS())
        settings.proMode = false
        XCTAssertFalse(IS_DESKTOP_COLUMNS())
    }

    func testFreshInstallDefaultsToProOnFirstUnfoldAndPreservesOptOut() {
        let suite = "NosturProDefaultTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.proMode),
                     "The fallback must not hide whether a preference was saved")
        settings.updatePhoneLayout(isExpanded: false)
        XCTAssertFalse(settings.usesProColumns)
        XCTAssertFalse(settings.proMode, "Compact phones retain their existing default")

        settings.updatePhoneLayout(isExpanded: true)
        XCTAssertTrue(settings.proMode)
        XCTAssertTrue(settings.usesProColumns)
        settings.updatePhoneLayout(isExpanded: false)
        XCTAssertTrue(settings.proMode)
        XCTAssertFalse(settings.usesProColumns)

        let relaunched = SettingsStore(defaults: defaults)
        relaunched.updatePhoneLayout(isExpanded: true)
        XCTAssertTrue(relaunched.usesProColumns)
        relaunched.proMode = false
        relaunched.updatePhoneLayout(isExpanded: false)
        relaunched.updatePhoneLayout(isExpanded: true)
        XCTAssertFalse(relaunched.proMode)

        let afterOptOut = SettingsStore(defaults: defaults)
        afterOptOut.updatePhoneLayout(isExpanded: true)
        XCTAssertFalse(afterOptOut.usesProColumns, "A saved opt-out survives relaunch and unfolding")
    }

    func testPhoneEligibilitySurvivesFoldingWithProDisabled() {
        let suite = "NosturProLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.proMode = false
        XCTAssertFalse(settings.phoneHasExpanded)
        settings.updatePhoneLayout(isExpanded: true)
        settings.updatePhoneLayout(isExpanded: false)
        XCTAssertFalse(settings.phoneIsExpanded)
        XCTAssertTrue(settings.phoneHasExpanded)
        XCTAssertFalse(settings.proMode)
    }
}
