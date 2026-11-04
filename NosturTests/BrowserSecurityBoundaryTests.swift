import CoreData
import UIKit
import WebKit
import XCTest
@testable import Nostur

@MainActor
final class BrowserSecurityBoundaryTests: XCTestCase {
    func testHomepageAppWorksWithFreshDefaultsWithoutPermissionSetup() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        XCTAssertTrue(fixture.browser.connected)
        XCTAssertTrue(fixture.browser.socialAllowed)
        XCTAssertTrue(fixture.browser.websiteAuthAllowed)
        XCTAssertTrue(fixture.browser.uploadsAllowed)
        let result = try await fixture.view.callAsyncJavaScript("""
        const key = await nostr.getPublicKey();
        const now = Math.floor(Date.now()/1000);
        const post = await nostr.signEvent({kind:1,created_at:now,tags:[],content:'hello'});
        const login = await nostr.signEvent({kind:27235,created_at:now,tags:[['u','https://primal.net/login'],['method','POST']],content:''});
        const preferences = await nostr.signEvent({kind:30078,created_at:now,tags:[['d','Primal-Web App','get_app_settings']],content:JSON.stringify({description:'Sync app settings'})});
        return {key, post:post.kind, login:login.kind, preferences:preferences.kind};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["key"] as? String, fixture.account.publicKey)
        XCTAssertEqual(result?["post"] as? Int, 1)
        XCTAssertEqual(result?["login"] as? Int, 27235)
        XCTAssertEqual(result?["preferences"] as? Int, 30078)
        XCTAssertEqual(fixture.signer.approvals.count, 3)
        // Optional user overrides still take precedence over defaults.
        fixture.browser.setConnected(false)
        fixture.attach()
        try await fixture.load()
        XCTAssertFalse(fixture.browser.connected)
    }

    func testWord5StartupAppDataWorksWithoutSetupAndDisconnectRevokesIt() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://otherstuff.ai")
        defer { fixture.close() }
        try await fixture.load()
        let script = """
        return await nostr.signEvent({kind:30078,created_at:Math.floor(Date.now()/1000),
          tags:[['schema','word5.chat.v1']],content:JSON.stringify({action:'rooms',nonce:'test'})});
        """
        let signed = try await fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(signed?["kind"] as? Int, 30078)
        XCTAssertNil(fixture.browser.notice)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        fixture.browser.setConnected(false)
        fixture.attach()
        try await fixture.load()
        let denied = try await fixture.view.callAsyncJavaScript("try { \(script) } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(denied as? Bool, true)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
    }

    func testWord5NewEventKindSignsWithoutPromptAndAppActionsToggleRevokesIt() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://otherstuff.ai")
        defer { fixture.close() }
        try await fixture.load()
        let script = """
        return await nostr.signEvent({kind:5555,created_at:Math.floor(Date.now()/1000),
          tags:[],content:'game request'});
        """
        let signed = try await fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(signed?["kind"] as? Int, 5555)
        XCTAssertTrue(fixture.browser.blockedRequests.isEmpty)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        fixture.browser.setSocial(false)
        let denied = try await fixture.view.callAsyncJavaScript("try { \(script) } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(denied as? Bool, true)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
    }

    func testCategoryControlsMergeUploadsAndKeepAccountAndWalletPermissionsScoped() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        XCTAssertFalse(fixture.browser.accountChangesAllowed)
        XCTAssertFalse(fixture.browser.deletionsAllowed)
        XCTAssertFalse(fixture.browser.walletAllowed)
        fixture.browser.setSocial(false)
        XCTAssertFalse(fixture.browser.uploadsAllowed)
        fixture.browser.setSocial(true)
        XCTAssertTrue(fixture.browser.uploadsAllowed)
        fixture.browser.setWallet(true)
        let script = """
        return await nostr.signEvent({kind:23194,created_at:Math.floor(Date.now()/1000),
          tags:[],content:'opaque wallet request'});
        """
        let signed = try await fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(signed?["kind"] as? Int, 23194)
        let grants = BrowserActionPermissions(preferences: fixture.preferences)
        for kind in [3, 5, 23194, 24242] {
            grants.allow(kind: kind, account: fixture.account.publicKey, origin: "https://primal.net", duration: .always)
        }
        fixture.browser.setSocial(false)
        XCTAssertFalse(fixture.browser.actionGrants.contains { $0.kind == 24242 })
        XCTAssertTrue(fixture.browser.actionGrants.contains { $0.kind == 3 })
        fixture.browser.setAccountChanges(false)
        XCTAssertFalse(fixture.browser.actionGrants.contains { $0.kind == 3 })
        XCTAssertTrue(fixture.browser.actionGrants.contains { $0.kind == 5 })
        fixture.browser.setDeletions(false)
        XCTAssertFalse(fixture.browser.actionGrants.contains { $0.kind == 5 })
        fixture.browser.setWallet(false)
        XCTAssertTrue(fixture.browser.actionGrants.isEmpty)
        async let denied = fixture.view.callAsyncJavaScript("try { \(script) } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { !fixture.browser.blockedRequests.isEmpty }
        fixture.browser.declineBlockedRequest(try XCTUnwrap(fixture.browser.blockedRequests.first?.id))
        let result = try await denied
        XCTAssertEqual(result as? Bool, true)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        fixture.browser.setAccountChanges(true)
        fixture.browser.setDeletions(true)
        fixture.browser.setWallet(true)
        fixture.browser.open(URL(string: "https://otherstuff.ai")!)
        XCTAssertFalse(fixture.browser.accountChangesAllowed)
        XCTAssertFalse(fixture.browser.deletionsAllowed)
        XCTAssertFalse(fixture.browser.walletAllowed)
    }

    func testWebsiteLoginStorageSurvivesHomeAndBrowserRecreation() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        _ = try await fixture.view.evaluateJavaScript("localStorage.setItem('login-test', 'remember-me')")
        fixture.browser.home()
        try await fixture.load()
        let homeValue = try await fixture.view.evaluateJavaScript("localStorage.getItem('login-test')") as? String
        XCTAssertEqual(homeValue, "remember-me")
        fixture.browser.close()
        let reopened = NostrBrowserModel(preferences: fixture.preferences)
        defer { reopened.close() }
        reopened.selectAccount(fixture.account)
        let view = try XCTUnwrap(reopened.webView)
        fixture.window.rootViewController?.view.addSubview(view)
        view.loadHTMLString("<html><body id='reopened'>ready</body></html>", baseURL: fixture.baseURL)
        try await fixture.waitUntil { !view.isLoading }
        // Wait for the new document instead of reading the initial about:blank.
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("document.body?.id")) as? String == "reopened" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let reopenedValue = try await view.evaluateJavaScript("localStorage.getItem('login-test')") as? String
        XCTAssertEqual(reopenedValue, "remember-me")
        await view.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func testRelayAuthenticationDenialsStayInActivityWithoutBanner() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        let denied = try await fixture.view.callAsyncJavaScript("""
        try {
            await nostr.signEvent({kind:22242,created_at:Math.floor(Date.now()/1000),
                tags:[['relay','wss://relay.example.invalid'],['challenge','test']],content:''});
            return false;
        } catch (_) { return true; }
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(denied as? Bool, true)
        XCTAssertNil(fixture.browser.notice)
        XCTAssertEqual(fixture.browser.activity.first?.blocked, true)
        XCTAssertTrue(fixture.browser.activity.first?.detail.contains("22242") == true)
        XCTAssertTrue(fixture.signer.approvals.isEmpty)

        _ = try await fixture.view.evaluateJavaScript("""
        nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[],content:''}).catch(()=>{}); true;
        """)
        try await fixture.waitUntil { !fixture.browser.blockedRequests.isEmpty }
        XCTAssertEqual(fixture.browser.blockedRequests.first?.kind, 3)
        XCTAssertNil(fixture.browser.notice)
        fixture.browser.declineBlockedRequest(try XCTUnwrap(fixture.browser.blockedRequests.first?.id))

        fixture.browser.setConnected(false)
        fixture.attach()
        try await fixture.load()
        fixture.browser.notice = nil
        let disconnectedDenied = try await fixture.view.callAsyncJavaScript("""
        try {
            await nostr.signEvent({kind:22242,created_at:Math.floor(Date.now()/1000),
                tags:[['relay','wss://relay.example.invalid'],['challenge','test']],content:''});
            return false;
        } catch (_) { return true; }
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(disconnectedDenied as? Bool, true)
        XCTAssertNil(fixture.browser.notice)
    }

    func testRealBridgeSharesOnlyExplicitlyConnectedIdentityAndApprovedEvents() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        try await fixture.load()
        XCTAssertFalse(fixture.browser.connected)
        XCTAssertFalse(fixture.browser.socialAllowed)
        XCTAssertFalse(fixture.browser.websiteAuthAllowed)
        XCTAssertFalse(fixture.browser.uploadsAllowed)
        let denied = try await fixture.view.callAsyncJavaScript("try { await nostr.getPublicKey(); return false; } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(denied as? Bool, true)
        fixture.browser.setConnected(true)
        fixture.attach()
        try await fixture.load()
        let publicKey = try await fixture.view.callAsyncJavaScript("return await nostr.getPublicKey();", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(publicKey as? String, fixture.account.publicKey)
        async let pendingPost = fixture.view.callAsyncJavaScript(Self.postScript(catching: true), arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { !fixture.browser.blockedRequests.isEmpty }
        fixture.browser.declineBlockedRequest(try XCTUnwrap(fixture.browser.blockedRequests.first?.id))
        let postDenied = try await pendingPost
        XCTAssertEqual(postDenied as? Bool, true)
        XCTAssertEqual(fixture.signer.approvals.count, 0)
        fixture.browser.setSocial(true)
        let signed = try await fixture.view.callAsyncJavaScript(Self.postScript(catching: false), arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(signed?["pubkey"] as? String, fixture.account.publicKey)
        XCTAssertEqual(Set(signed?.keys.map { $0 } ?? []), ["id", "pubkey", "created_at", "kind", "tags", "content", "sig"])
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        XCTAssertEqual(fixture.signer.approvals.first?.accountPubkey, fixture.account.publicKey)
    }

    func testStaleDocumentTokenAndCanceledSignaturesCannotCrossNavigationOrMinimize() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        try await fixture.load()
        fixture.browser.setConnected(true)
        fixture.attach()
        try await fixture.load()
        fixture.browser.setSocial(true)
        let oldToken = try await fixture.token()
        try await fixture.load(marker: "second-document")
        let newToken = try await fixture.token()
        XCTAssertNotEqual(newToken, oldToken)
        let staleDenied = try await fixture.view.callAsyncJavaScript("""
        try {
          await window.webkit.messageHandlers.nostur.postMessage(JSON.stringify({documentToken:oldToken,method:'getPublicKey',event:null}));
          return false;
        } catch (_) { return true; }
        """, arguments: ["oldToken": oldToken], in: nil, contentWorld: BrowserBridge.world)
        XCTAssertEqual(staleDenied as? Bool, true)
        fixture.signer.automatic = false
        _ = try await fixture.view.evaluateJavaScript("""
        window.signatureOutcome = 'pending';
        nostr.signEvent({kind:1,created_at:Math.floor(Date.now()/1000),tags:[],content:'draft'})
          .then(() => { window.signatureOutcome='signed'; }, () => { window.signatureOutcome='denied'; });
        true;
        """)
        try await fixture.waitUntil { !fixture.signer.approvals.isEmpty }
        fixture.browser.setPresented(false)
        XCTAssertFalse(fixture.signer.canceled.isEmpty)
        fixture.signer.deliverLateResults()
        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = try await fixture.view.evaluateJavaScript("window.signatureOutcome") as? String
        XCTAssertEqual(outcome, "denied")
        fixture.browser.setPresented(true)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
    }

    func testAccountSwitchReplacesWebStorageAndDoesNotTransferPermissions() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        try await fixture.load()
        fixture.browser.setConnected(true)
        fixture.attach()
        try await fixture.load()
        fixture.browser.setSocial(true)
        let oldView = fixture.view
        let oldStore = oldView.configuration.websiteDataStore
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "security.example.invalid", .path: "/", .name: "private-service-session", .value: "account-a-only"]))
        await withCheckedContinuation { continuation in oldStore.httpCookieStore.setCookie(cookie) { continuation.resume() } }
        let second = CloudAccount(entity: fixture.account.entity, insertInto: fixture.context)
        second.publicKey = String(repeating: "b", count: 64)
        second.name = "Other browser test"
        AccountsState.shared.accounts.append(second)
        fixture.browser.selectAccount(second)
        fixture.attach()
        XCTAssertFalse(fixture.view === oldView)
        XCTAssertFalse(fixture.view.configuration.websiteDataStore === oldStore)
        try await fixture.load()
        XCTAssertFalse(fixture.browser.connected)
        XCTAssertFalse(fixture.browser.socialAllowed)
        let cookies = await withCheckedContinuation { continuation in
            fixture.view.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(cookies.contains { $0.name == "private-service-session" })
    }

    func testNativeApprovalCompletesExactPendingRequestAndRemembersOnlyItsKind() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        _ = try await fixture.view.evaluateJavaScript("""
        window.grantOutcome = 'pending';
        nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[['p','chosen']],content:''})
            .then(e=>{window.grantOutcome=e.kind;},()=>{window.grantOutcome='denied';}); true;
        """)
        try await fixture.waitUntil { fixture.browser.blockedRequests.contains { $0.kind == 3 } }
        let item = try XCTUnwrap(fixture.browser.blockedRequests.first)
        XCTAssertTrue(fixture.browser.canAllow(item))
        XCTAssertNil(fixture.browser.notice)
        XCTAssertTrue(fixture.signer.approvals.isEmpty)
        fixture.browser.allowBlockedRequest(item.id, duration: .today)
        try await fixture.waitUntil { fixture.signer.approvals.count == 1 }
        XCTAssertEqual(fixture.signer.approvals.first?.event.tags, [["p", "chosen"]])
        XCTAssertEqual(fixture.browser.actionGrants.map(\.kind), [3])
        let again = try await fixture.view.callAsyncJavaScript("""
        return (await nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[],content:''})).kind;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(again as? Int, 3)
        _ = try await fixture.view.evaluateJavaScript("""
        nostr.signEvent({kind:10002,created_at:Math.floor(Date.now()/1000),tags:[],content:''}).catch(()=>{}); true;
        """)
        try await fixture.waitUntil { fixture.browser.blockedRequests.contains { $0.kind == 10002 } }
        let stale = try XCTUnwrap(fixture.browser.blockedRequests.first { $0.kind == 10002 })
        fixture.browser.setPresented(false)
        fixture.browser.allowBlockedRequest(stale.id, duration: .always)
        XCTAssertFalse(fixture.browser.actionGrants.contains { $0.kind == 10002 })
        XCTAssertEqual(fixture.signer.approvals.count, 2)
        fixture.browser.revokeAction(3)
        XCTAssertTrue(fixture.browser.actionGrants.isEmpty)
    }

    func testExpiredApprovalSavesOnlyFuturePermissionAndRevocationStopsLateReply() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net", approvalWaitSeconds: 1)
        defer { fixture.close() }
        try await fixture.load()
        let script = """
        window.expiryOutcome = 'pending';
        nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[],content:''})
            .then(()=>{window.expiryOutcome='signed';},()=>{window.expiryOutcome='denied';}); true;
        """
        _ = try await fixture.view.evaluateJavaScript(script)
        try await fixture.waitUntil { fixture.browser.blockedRequests.contains { !$0.waiting } }
        let expired = try XCTUnwrap(fixture.browser.blockedRequests.first)
        fixture.browser.allowBlockedRequest(expired.id, duration: .always)
        XCTAssertTrue(fixture.signer.approvals.isEmpty, "Expired events must not be revived")
        XCTAssertEqual(fixture.browser.actionGrants.map(\.kind), [3])
        fixture.signer.automatic = false
        _ = try await fixture.view.evaluateJavaScript(script)
        try await fixture.waitUntil { fixture.signer.approvals.count == 1 }
        fixture.browser.revokeAction(3)
        fixture.signer.deliverLateResults()
        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = try await fixture.view.evaluateJavaScript("window.expiryOutcome") as? String
        XCTAssertEqual(outcome, "denied")
        XCTAssertTrue(fixture.browser.actionGrants.isEmpty)
    }

    private static func postScript(catching: Bool) -> String {
        let call = "await nostr.signEvent({kind:1,created_at:Math.floor(Date.now()/1000),tags:[],content:'hello',pubkey:'attacker',privateKey:'export'})"
        return catching ? "try { \(call); return false; } catch (_) { return true; }" : "return \(call);"
    }
}

@MainActor
private final class BrowserSecurityFixture {
    let context: NSManagedObjectContext
    let account: CloudAccount
    let signer = BoundaryTestSigner()
    let browser: NostrBrowserModel
    let window: UIWindow
    let preferences: UserDefaults
    let baseURL: URL
    let suite = "browser.security.test." + UUID().uuidString
    var view: WKWebView { browser.webView }

    init(origin: String = "https://security.example.invalid", approvalWaitSeconds: UInt64 = 120) throws {
        baseURL = try XCTUnwrap(URL(string: origin))
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        account = CloudAccount(entity: try XCTUnwrap(model.entitiesByName["CloudAccount"]), insertInto: context)
        account.publicKey = String(repeating: "a", count: 64)
        account.name = "Browser boundary test"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        browser = NostrBrowserModel(relaySettingsProvider: { [] }, signer: signer, preferences: preferences, approvalWaitSeconds: approvalWaitSeconds)
        browser.selectAccount(account)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        AccountsState.shared.accounts.append(account)
        browser.setPresented(true)
        attach()
    }

    func attach() {
        window.rootViewController?.view.subviews.forEach { $0.removeFromSuperview() }
        view.frame = window.rootViewController?.view.bounds ?? window.bounds
        window.rootViewController?.view.addSubview(view)
    }

    func load(marker: String = "first-document") async throws {
        browser.open(baseURL)
        view.stopLoading()
        view.loadHTMLString("<html><body><p id='marker'>\(marker)</p></body></html>", baseURL: baseURL)
        let deadline = Date().addingTimeInterval(7)
        while Date() < deadline {
            let actual = try? await view.evaluateJavaScript("document.getElementById('marker')?.textContent") as? String
            let token = try? await token()
            if actual == marker, token != nil, UIApplication.shared.applicationState == .active { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The real isolated browser bridge did not become ready")
        throw BrowserSigningFailure.timeout
    }

    func token() async throws -> String {
        let value = try await view.callAsyncJavaScript("return globalThis.__nosturDocumentToken;", arguments: [:], in: nil, contentWorld: BrowserBridge.world)
        guard let token = value as? String, UUID(uuidString: token) != nil else { throw BrowserSigningFailure.failed }
        return token
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 25_000_000) }
        XCTAssertTrue(condition())
    }

    func close() {
        browser.close()
        window.isHidden = true
        AccountsState.shared.accounts.removeAll { $0.managedObjectContext === context }
        preferences.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class BoundaryTestSigner: BrowserEventSigning {
    var approvals: [BrowserSigningApproval] = []
    var canceled: Set<UUID> = []
    var automatic = true
    private var completions: [(BrowserSigningApproval, @MainActor @Sendable (Result<BrowserSignedEvent, BrowserSigningFailure>) -> Void)] = []

    func sign(_ approval: BrowserSigningApproval, requestID: UUID, completion: @escaping @MainActor @Sendable (Result<BrowserSignedEvent, BrowserSigningFailure>) -> Void) {
        approvals.append(approval)
        if automatic { completion(.success(Self.result(approval))) }
        else { completions.append((approval, completion)) }
    }
    func cancel(_ requestID: UUID) { canceled.insert(requestID) }
    func deliverLateResults() {
        for (approval, completion) in completions { completion(.success(Self.result(approval))) }
        completions.removeAll()
    }
    private static func result(_ approval: BrowserSigningApproval) -> BrowserSignedEvent {
        BrowserSignedEvent(id: String(repeating: "1", count: 64), pubkey: approval.accountPubkey,
                           created_at: approval.event.created_at, kind: approval.event.kind, tags: approval.event.tags,
                           content: approval.event.content, sig: String(repeating: "2", count: 128))
    }
}
