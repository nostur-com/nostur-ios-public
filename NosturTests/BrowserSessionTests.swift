import CoreData
import WebKit
import SwiftUI
import XCTest
@testable import Nostur

@MainActor
final class BrowserSessionTests: XCTestCase {
    func testPostLinkOpensExistingMinimizedSessionAndRejectsUnsafeSchemes() throws {
        let session = NostrBrowserSession()
        defer { session.close() }
        session.open(URL(string: "file:///private/test")!)
        XCTAssertNil(session.browser)
        session.present()
        let browser = try XCTUnwrap(session.browser)
        session.minimize()
        let url = URL(string: "https://example.invalid/post-link")!
        session.open(url)
        browser.webView.stopLoading()
        XCTAssertTrue(session.browser === browser)
        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(browser.currentURL, url)
        XCTAssertFalse(browser.connected)
    }

    func testMinimizeAndResumePreserveLivePageDraftAndSessionCookies() async throws {
        let session = NostrBrowserSession()
        session.present()
        let browser = try XCTUnwrap(session.browser)
        let view = try XCTUnwrap(browser.webView)
        defer { session.close() }
        let observer = BrowserSessionPageObserver()
        view.navigationDelegate = observer
        let loaded = expectation(description: "Local page loaded")
        observer.loaded = { BrowserBridge.activate(view, token: UUID().uuidString); loaded.fulfill() }
        view.loadHTMLString("<html><body><input id='draft' value='unfinished post'></body></html>", baseURL: URL(string: "https://example.test"))
        await fulfillment(of: [loaded], timeout: 10)
        _ = try await view.evaluateJavaScript("window.browserSessionMarker = 'keep-me'")
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.test", .path: "/", .name: "test-session", .value: "still-signed-in"]))
        await withCheckedContinuation { continuation in
            view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        session.minimize()
        XCTAssertTrue(session.isMinimized)
        XCTAssertFalse(browser.isPresented)
        XCTAssertTrue(session.browser === browser)
        // Exercise the real native bridge while minimized. No fake signing keys
        // or external website requests are involved in this test.
        let rejected = try await view.callAsyncJavaScript("""
        try { await window.nostr.getPublicKey(); return false; }
        catch (_) { return true; }
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(rejected as? Bool, true)
        session.present()
        XCTAssertTrue(session.isPresented)
        XCTAssertTrue(browser.isPresented)
        XCTAssertTrue(session.browser?.webView === view)
        let marker = try await view.evaluateJavaScript("window.browserSessionMarker") as? String
        let draft = try await view.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(marker, "keep-me")
        XCTAssertEqual(draft, "unfinished post")
        let cookies = await withCheckedContinuation { continuation in
            view.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(cookies.contains { $0.name == "test-session" && $0.value == "still-signed-in" })
        session.close()
        XCTAssertNil(session.browser)
        XCTAssertFalse(browser.isPresented)
        session.present()
        XCTAssertFalse(session.browser === browser)
        XCTAssertTrue(session.browser?.isHome == true)
    }

    func testMinimizeAndResumeDoNotWaitForBlockedCoreDataQueue() async {
        let session = NostrBrowserSession()
        session.present()
        defer { session.close() }
        let managedContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedContext.persistentStoreCoordinator = DataProvider.shared().container.persistentStoreCoordinator
        let started = expectation(description: "Core Data queue held")
        let completed = expectation(description: "UI minimizes and resumes while queue is held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        Self.holdQueue(managedContext, started: started, release: release)
        await fulfillment(of: [started], timeout: 2)
        let lookup = Task { await BrowserRelaySettings.snapshot(in: managedContext) }
        Task { @MainActor in
            session.minimize()
            XCTAssertFalse(session.browser?.isPresented ?? true)
            session.present()
            XCTAssertTrue(session.browser?.isPresented ?? false)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        release.signal()
        _ = await lookup.value
    }

    private nonisolated static func holdQueue(_ managedContext: NSManagedObjectContext, started: XCTestExpectation, release: DispatchSemaphore) {
        managedContext.perform {
            started.fulfill()
            release.wait()
        }
    }

    func testFullScreenPresentationCanMinimizeAndReturnToSamePage() async throws {
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let managedContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedContext.persistentStoreCoordinator = coordinator
        let account = CloudAccount(entity: try XCTUnwrap(model.entitiesByName["CloudAccount"]), insertInto: managedContext)
        account.publicKey = String(repeating: "c", count: 64)
        account.name = "Browser test"
        account.flagsSet = ["nostur_created", "full_account"]
        let session = NostrBrowserSession()
        let root = Color.clear
            .modifier(NostrBrowserPresentation(session: session, account: LoggedInAccount(account)))
            .environment(\.managedObjectContext, managedContext)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        defer { session.close(); window.isHidden = true }
        // Wait for the host before requesting a full-screen cover.
        try await Task.sleep(nanoseconds: 100_000_000)
        session.present()
        await waitUntil {
            guard let controller = window.rootViewController?.presentedViewController else { return false }
            return !controller.isBeingPresented && controller.transitionCoordinator == nil
        }
        let browser = try XCTUnwrap(session.browser)
        XCTAssertEqual(browser.accountPubkey, account.publicKey)
        browser.open(URL(string: "https://example.invalid")!)
        let view = try XCTUnwrap(browser.webView)
        view.stopLoading()
        let observer = BrowserSessionPageObserver()
        view.navigationDelegate = observer
        let loaded = expectation(description: "Presented browser loads local page")
        observer.loaded = { BrowserBridge.activate(view, token: UUID().uuidString); loaded.fulfill() }
        view.loadHTMLString("<html><body><input id='draft' value='draft survives presentation'></body></html>", baseURL: URL(string: "https://example.invalid"))
        await fulfillment(of: [loaded], timeout: 10)
        session.minimize()
        await waitUntil { window.rootViewController?.presentedViewController == nil }
        XCTAssertTrue(session.isMinimized)
        XCTAssertFalse(browser.isPresented)
        session.present()
        await waitUntil {
            guard let controller = window.rootViewController?.presentedViewController else { return false }
            return !controller.isBeingPresented && controller.transitionCoordinator == nil
        }
        XCTAssertTrue(session.browser === browser)
        XCTAssertTrue(browser.webView === view)
        let draft = try await view.evaluateJavaScript("document.getElementById('draft').value") as? String
        XCTAssertEqual(draft, "draft survives presentation")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class BrowserSessionPageObserver: NSObject, WKNavigationDelegate {
    var loaded: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?()
        loaded = nil
    }
}
