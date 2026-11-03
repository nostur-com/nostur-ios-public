import NavigationBackport
import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class NosturProLayoutTests: XCTestCase {
    @available(iOS 17.0, *)
    func testMainColumnPagerFillsTheSameHeightAsAdjacentColumn() async throws {
        try XCTSkipUnless(IS_IPHONE, "Phone pager regression")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var mainFrame = CGRect.zero
        var adjacentFrame = CGRect.zero
        let host = UIHostingController(rootView: ProSidebarLayout {
            Color.gray.frame(width: SIDEBAR_WIDTH)
        } columns: {
            HStack(spacing: 1) {
                TabView(selection: .constant("Main")) {
                    NBNavigationStack {
                        List(0..<30) { Text("Main row \($0)") }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mainFrame = $0 }
                            .navigationTitle("Main")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .nbUseNavigationStack(.never)
                    .environment(\.horizontalSizeClass, .compact)
                    .modifier(ProMainColumnTabBarHidden())
                    .tag("Main")
                    Text("Other tab").modifier(ProMainColumnTabBarHidden()).tag("Other")
                }
                .modifier(ProMainColumnTabsStyle())
                NBNavigationStack {
                    List(0..<30) { Text("Adjacent row \($0)") }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { adjacentFrame = $0 }
                        .navigationTitle("Adjacent")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .nbUseNavigationStack(.never)
            }
        })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for bottomInset in [CGFloat(0), 40, 0] {
            host.additionalSafeAreaInsets.bottom = bottomInset
            window.layoutIfNeeded()
            // Allow navigation and paging controllers to complete their layout passes.
            try await Task.sleep(for: .milliseconds(500))
            // SwiftUI geometry excludes the safe area in both columns; the bug
            // is the pager clipping the underlying scroll view's drawing region.
            let lists = scrollViews(in: host.view).filter { $0.contentSize.height > $0.bounds.height }
                .sorted { $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX }
            XCTAssertEqual(lists.count, 2)
            if lists.count == 2 {
                let mainVisible = visibleFrame(of: lists[0], in: window)
                let adjacentVisible = visibleFrame(of: lists[1], in: window)
                XCTAssertEqual(mainVisible.maxY, adjacentVisible.maxY, accuracy: 1,
                               "Pager must not clip the feed above its neighboring column: main \(mainVisible), adjacent \(adjacentVisible)")
            }
            XCTAssertGreaterThan(mainFrame.height, 0)
            XCTAssertGreaterThan(adjacentFrame.height, 0)
            XCTAssertEqual(mainFrame.maxY, adjacentFrame.maxY, accuracy: 1,
                           "Main pager must not reserve an extra bottom strip: main \(mainFrame), adjacent \(adjacentFrame)")
        }
    }

    @available(iOS 27.1, *)
    func testMainColumnKeepsSelectionAndScrollPositionDuringAdjacentPopover() async throws {
        try XCTSkipUnless(IS_IPHONE, "Duo main column")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let selection = ProMenuSelection()
        var anchor: UIView?
        var mainFrame = CGRect.zero
        let host = UIHostingController(rootView: GeometryReader { geometry in
            ProColumnOrder {
                TabView(selection: Binding(get: { selection.tab }, set: { selection.tab = $0 })) {
                    Text("Following").modifier(ProMainColumnTabBarHidden()).tag("Main")
                    List(0..<50) { Text("Search result \($0)") }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mainFrame = $0 }
                        .modifier(ProMainColumnTabBarHidden())
                        .tag("Search")
                }
                .modifier(ProMainColumnTabsStyle())
                .frame(width: (geometry.size.width - COLUMN_SPACING) / 2)
            } extraColumns: {
                ProFeedHitProbe { anchor = $0 }
            }
        })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
        XCTAssertEqual(selection.tab, "Search")
        let list = try XCTUnwrap(scrollViews(in: host.view).first { $0.contentSize.height > $0.bounds.height })
        list.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
        let originalOffset = list.contentOffset
        let originalFrame = mainFrame
        let adjacentView = try XCTUnwrap(anchor)
        XCTAssertGreaterThanOrEqual(mainFrame.minX, adjacentView.convert(adjacentView.bounds, to: window).maxX,
                                    "The sidebar-controlled column belongs on the right of independent feeds")
        XCTAssertFalse(hasVisibleTabBar(in: host.view, window: window), "Pro selection belongs to the app rail, not a second tab bar")
        XCTAssertGreaterThan(originalFrame.width, 0)
        XCTAssertFalse(hasPageController(in: host), "The main column must not swipe between sidebar tabs")

        let popover = UIViewController()
        popover.view.backgroundColor = .secondarySystemBackground
        popover.preferredContentSize = CGSize(width: 220, height: 350)
        popover.modalPresentationStyle = .popover
        let source = try XCTUnwrap(anchor)
        popover.popoverPresentationController?.sourceView = source
        popover.popoverPresentationController?.sourceRect = CGRect(x: source.bounds.width - 40, y: 0, width: 40, height: 40)
        await withCheckedContinuation { continuation in
            host.present(popover, animated: false) { continuation.resume() }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
        XCTAssertEqual(selection.tab, "Search")
        XCTAssertEqual(mainFrame.minX, originalFrame.minX, accuracy: 1)
        XCTAssertEqual(mainFrame.width, originalFrame.width, accuracy: 1)
        XCTAssertTrue(list.window === window, "The selected tab's scroll view must remain attached")
        XCTAssertTrue(scrollViews(in: host.view).contains { $0 === list })
        XCTAssertTrue(visibleFrame(of: list, in: window).intersects(window.bounds))
        XCTAssertEqual(list.contentOffset.x, originalOffset.x, accuracy: 1)
        XCTAssertEqual(list.contentOffset.y, originalOffset.y, accuracy: 1)
        await withCheckedContinuation { continuation in
            popover.dismiss(animated: false) { continuation.resume() }
        }
        XCTAssertEqual(selection.tab, "Search")
        XCTAssertTrue(list.window === window)
        XCTAssertEqual(list.contentOffset.y, originalOffset.y, accuracy: 1)
    }

    @available(iOS 17.0, *)
    func testColumnOrderKeepsPrimaryBesideSidebarAndRetainsItWhenAddingAFeed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        for primaryOnRight in [true, false] {
            let state = ProColumnCountProbe()
            var primaryView: UIView?
            var extras: [Int: UIView] = [:]
            let host = UIHostingController(rootView: ProColumnOrderProbe(state: state, primaryOnRight: primaryOnRight, onPrimary: { primaryView = $0 }, onExtra: { extras[$0] = $1 }))
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(200))
            let originalPrimary = try XCTUnwrap(primaryView)
            for count in [1, 2, 1] {
                state.count = count
                try await Task.sleep(for: .milliseconds(200))
                window.layoutIfNeeded()
                XCTAssertTrue(primaryView === originalPrimary)
                XCTAssertTrue(originalPrimary.window === window)
                let main = originalPrimary.convert(originalPrimary.bounds, to: window)
                let first = try XCTUnwrap(extras[0])
                let firstFrame = first.convert(first.bounds, to: window)
                if primaryOnRight {
                    XCTAssertGreaterThan(main.minX, firstFrame.maxX)
                    if count == 2 {
                        let second = try XCTUnwrap(extras[1])
                        let secondFrame = second.convert(second.bounds, to: window)
                        XCTAssertGreaterThan(secondFrame.minX, firstFrame.maxX)
                        XCTAssertGreaterThan(main.minX, secondFrame.maxX)
                    }
                }
                else {
                    XCTAssertLessThan(main.maxX, firstFrame.minX, "Catalyst retains its primary column on the left")
                }
            }
        }
    }

    private func hasVisibleTabBar(in view: UIView, window: UIWindow) -> Bool {
        if view is UITabBar, !view.isHidden, view.alpha > 0.01,
           visibleFrame(of: view, in: window).intersects(window.bounds) {
            var ancestor = view.superview
            var hidden = false
            while let current = ancestor {
                hidden = hidden || current.isHidden || current.alpha < 0.01
                ancestor = current.superview
            }
            if !hidden { return true }
        }
        return view.subviews.contains { hasVisibleTabBar(in: $0, window: window) }
    }

    private func hasPageController(in controller: UIViewController) -> Bool {
        controller is UIPageViewController || controller.children.contains { hasPageController(in: $0) }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        let current = (view as? UIScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func visibleFrame(of view: UIView, in window: UIWindow) -> CGRect {
        var frame = view.convert(view.bounds, to: window)
        var ancestor = view.superview
        while let parent = ancestor {
            if parent.clipsToBounds {
                frame = frame.intersection(parent.convert(parent.bounds, to: window))
            }
            ancestor = parent.superview
        }
        return frame
    }

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

    @available(iOS 27.1, *)
    func testProControlsUseSystemBarRegionAndColumnsHaveNoLeftRail() async throws {
        try XCTSkipUnless(IS_IPHONE, "Duo layout")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let suite = "DuoNativeBar-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = MacColumnsVM(defaults: defaults)
        var frame = CGRect.zero
        var feedView: UIView?
        let laidOut = expectation(description: "Columns rendered inside native navigation host")
        var didLayout = false
        let host = UIHostingController(rootView: ProSidebarLayout {
            Color.red.frame(width: SIDEBAR_WIDTH)
        } columns: {
            ProFeedHitProbe { feedView = $0 }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                frame = $0
                if !didLayout { didLayout = true; laidOut.fulfill() }
            }
        }
        .modifier(DuoProNavigation(vm: vm))
        .environmentObject(DMsVM.shared))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [laidOut], timeout: 5)
        window.layoutIfNeeded()
        let safe = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: window)
        XCTAssertEqual(frame.minX, safe.minX, accuracy: 1)
        XCTAssertEqual(frame.maxX, safe.maxX, accuracy: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
        let controller = try XCTUnwrap(railController(in: host))
        XCTAssertFalse(controller.host.view.isHidden, "The active unfolded pose must expose a system bar")
        let railFrame = controller.host.view.convert(controller.host.view.bounds, to: window)
        XCTAssertGreaterThan(railFrame.width, 0)
        if railFrame.midX > window.bounds.midX {
            XCTAssertGreaterThanOrEqual(railFrame.minX, safe.maxX - 1)
        }
        else {
            XCTAssertLessThanOrEqual(railFrame.maxX, safe.minX + 1)
        }
        XCTAssertGreaterThan(railFrame.minY, safe.minY, "The rail must clear the system status controls")
        let railHit = window.hitTest(CGPoint(x: railFrame.midX, y: railFrame.minY + 75), with: nil)
        XCTAssertTrue(railHit?.isDescendant(of: controller.host.view) == true,
                      "Touches in the rail must reach its hosted controls")
        let feedHit = window.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
        let feed = try XCTUnwrap(feedView)
        XCTAssertTrue(feedHit?.isDescendant(of: feed) == true,
                      "Feed touches must pass through the transparent bar host to the feed")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Duo native Pro controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @available(iOS 27.1, *)
    func testColumnToolbarStaysInColumnBesideSystemRail() async throws {
        try XCTSkipUnless(IS_IPHONE, "Duo layout")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var actionFrame = CGRect.zero
        var columnFrame = CGRect.zero
        let rendered = expectation(description: "Column action rendered")
        var didRender = false
        let host = UIHostingController(rootView: GeometryReader { geometry in
            let width = (geometry.size.width - 3 * COLUMN_SPACING) / 2
            ProSidebarLayout {
                Color.clear.frame(width: SIDEBAR_WIDTH)
            } columns: {
                HStack(spacing: COLUMN_SPACING) {
                    Color.blue.frame(width: width)
                    NBNavigationStack {
                        Color.blue
                            .navigationTitle("Column")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Color.red.frame(width: 30, height: 30)
                                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                            actionFrame = $0
                                            if !didRender { didRender = true; rendered.fulfill() }
                                        }
                                }
                                .axisBehavior(.verticalPreferred)
                            }
                    }
                    .nbUseNavigationStack(.whenAvailable)
                    .frame(width: width)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { columnFrame = $0 }
                }
            }
        }
        .modifier(DuoProNavigation(vm: .shared))
        .environmentObject(DMsVM.shared))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [rendered], timeout: 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        window.layoutIfNeeded()
        let rail = try XCTUnwrap(railController(in: host))
        XCTAssertFalse(rail.host.view.isHidden, "Column navigation must not disable the system's vertical region")
        XCTAssertGreaterThan(actionFrame.width, 0)
        XCTAssertGreaterThanOrEqual(actionFrame.minX, columnFrame.minX - 1)
        XCTAssertLessThanOrEqual(actionFrame.maxX, columnFrame.maxX + 1,
                                 "Column toolbar content must not migrate into the app rail")
        let attachment = XCTAttachment(string: "Column \(columnFrame); action \(actionFrame)")
        attachment.name = "Column toolbar stays local"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @available(iOS 27.1, *)
    private func railController(in controller: UIViewController) -> DuoProRailController? {
        if let rail = controller as? DuoProRailController { return rail }
        return controller.children.lazy.compactMap { self.railController(in: $0) }.first
    }

    func testDuoColumnToggleRetainsHiddenFeedAndChoiceAcrossRelaunch() throws {
        let suite = "DuoCountTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = [MacColumnConfig(type: .notifications("account")), MacColumnConfig(type: .hot), MacColumnConfig(type: .emoji)]
        let data = try JSONEncoder().encode(MacListStateSerialized(columns: saved))
        defaults.set(String(decoding: data, as: UTF8.self), forKey: "mac_columns_serialized")
        let vm = MacColumnsVM(defaults: defaults)
        vm.restoreConfiguredColumns(defaultPhoneAccount: nil)
        XCTAssertEqual(vm.duoColumnCount, 3)
        XCTAssertEqual(vm.duoColumns, Array(saved.prefix(2)), "Existing four-column layouts must display at most three total")
        vm.setDuoColumnCount(2)
        XCTAssertEqual(vm.duoColumns, Array(saved.prefix(1)))
        XCTAssertEqual(vm.columns, saved, "Reducing the visible count must retain configured feeds")
        vm.setDuoColumnCount(3)
        XCTAssertEqual(vm.duoColumns, Array(saved.prefix(2)))
        vm.setDuoColumnCount(2)
        let relaunched = MacColumnsVM(defaults: defaults)
        relaunched.restoreConfiguredColumns(defaultPhoneAccount: nil)
        XCTAssertEqual(relaunched.duoColumnCount, 2)
        XCTAssertEqual(relaunched.duoColumns.count, 1)
        XCTAssertEqual(relaunched.columns, saved)
        relaunched.setDuoColumnCount(3)
        XCTAssertEqual(relaunched.duoColumns[1].id, saved[1].id)
        if IS_IPHONE {
            XCTAssertFalse(relaunched.allowAddColumn)
            relaunched.addColumn(MacColumnConfig(type: .search))
            XCTAssertEqual(relaunched.columns, saved, "Other add-column entry points must not create a fourth Duo column")
            let replacement = MacColumnConfig(type: .search)
            relaunched.addOrReplaceColumn(replacement)
            XCTAssertEqual(relaunched.duoColumns, [saved[0], replacement])
            XCTAssertEqual(relaunched.columns[2], saved[2], "Replacing the visible last slot must preserve migrated hidden configurations")
            XCTAssertEqual(relaunched.columns.count, saved.count)
        }
    }

    func testDuoColumnToggleCreatesOnlyOneOptionalColumn() {
        let suite = "DuoCountFreshTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = MacColumnsVM(defaults: defaults)
        vm.prepareDuoColumns(defaultPhoneAccount: "account")
        XCTAssertEqual(vm.duoColumns.count, 1)
        XCTAssertEqual(vm.duoColumns.first?.type, .notifications("account"))
        vm.setDuoColumnCount(3)
        let thirdColumnID = vm.duoColumns[1].id
        vm.setDuoColumnCount(2)
        vm.setDuoColumnCount(3)
        XCTAssertEqual(vm.duoColumns[1].id, thirdColumnID)
        XCTAssertEqual(vm.columns.count, 2)
    }

    @available(iOS 17.0, *)
    func testAccountDrawerPlacementAndClosingDirection() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        var drawerView: UIView?
        func root(shown: Bool, right: Bool, direction: LayoutDirection) -> some View {
            SidebarDrawerLayout(isShown: shown, opensFromRight: right, clampsWidth: true) {
                ProFeedHitProbe { drawerView = $0 }
            }
            .environment(\.layoutDirection, direction)
        }
        let host = UIHostingController(rootView: root(shown: true, right: true, direction: .leftToRight))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            host.rootView = root(shown: true, right: true, direction: direction)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            let drawer = try XCTUnwrap(drawerView)
            let safe = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: window)
            let frame = drawer.convert(drawer.bounds, to: window)
            XCTAssertEqual(frame.maxX, safe.maxX, accuracy: 1, "Unfolded account drawer must anchor physically right")
            XCTAssertEqual(frame.width, min(NOSTUR_SIDEBAR_WIDTH, safe.width), accuracy: 1)
            host.rootView = root(shown: false, right: true, direction: direction)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            let closed = drawer.convert(drawer.bounds, to: window)
            XCTAssertGreaterThanOrEqual(closed.minX, safe.maxX - 1, "Closing moves out through the right edge")
        }
        host.rootView = root(shown: true, right: false, direction: .leftToRight)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        let drawer = try XCTUnwrap(drawerView)
        let safe = host.view.convert(host.view.safeAreaLayoutGuide.layoutFrame, to: window)
        XCTAssertEqual(drawer.convert(drawer.bounds, to: window).minX, safe.minX, accuracy: 1,
                       "Existing left-drawer layout must remain unchanged")
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

private struct ProFeedHitProbe: UIViewRepresentable {
    var onCreated: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBlue
        onCreated(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

@MainActor
private final class ProMenuSelection {
    var tab = "Search"
}

@MainActor
private final class ProColumnCountProbe: ObservableObject {
    @Published var count = 1
}

private struct ProColumnOrderProbe: View {
    @ObservedObject var state: ProColumnCountProbe
    var primaryOnRight: Bool
    var onPrimary: (UIView) -> Void
    var onExtra: (Int, UIView) -> Void

    var body: some View {
        ProColumnOrder(primaryOnRight: primaryOnRight) {
            ProFeedHitProbe(onCreated: onPrimary).frame(width: 150)
        } extraColumns: {
            ForEach(0..<state.count, id: \.self) { index in
                ProFeedHitProbe { onExtra(index, $0) }.frame(width: 150)
            }
        }
    }
}
