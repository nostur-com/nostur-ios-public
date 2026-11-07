import CoreData
import UIKit
import WebKit
import XCTest
@testable import Nostur

@MainActor
final class BrowserSecurityBoundaryTests: XCTestCase {
    func testPrimaryHomepageAppsCanConnectSignAndResumeWithoutSetup() async throws {
        let origins = ["https://jumble.social", "https://primal.net", "https://account.nostr.build",
                       "https://otherstuff.ai", "https://honey.hivetalk.org"]
        for origin in origins {
            let fixture = try BrowserSecurityFixture(origin: origin)
            defer { fixture.close() }
            try await fixture.load()
            XCTAssertTrue(fixture.browser.connected, origin)
            let first = try await fixture.view.callAsyncJavaScript("""
            const key = await nostr.getPublicKey();
            localStorage.setItem('browser-app-session', key);
            const event = await nostr.signEvent({kind:30078,created_at:Math.floor(Date.now()/1000),
              tags:[['d','app-preferences']],content:'preferences'});
            window.browserDraft = 'unfinished';
            return {key,kind:event.kind};
            """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            XCTAssertEqual(first?["key"] as? String, fixture.account.publicKey, origin)
            XCTAssertEqual(first?["kind"] as? Int, 30078, origin)
            fixture.browser.setPresented(false)
            fixture.browser.setPresented(true)
            let draft = try await fixture.view.evaluateJavaScript("window.browserDraft") as? String
            XCTAssertEqual(draft, "unfinished", origin)
            fixture.browser.home()
            try await fixture.load()
            let session = try await fixture.view.evaluateJavaScript("localStorage.getItem('browser-app-session')") as? String
            XCTAssertEqual(session, fixture.account.publicKey, origin)
            XCTAssertTrue(fixture.browser.blockedRequests.isEmpty, origin)
        }
    }

    func testFullFollowingAndMuteListsRequireApprovalAndResumeTheOriginalRequest() async throws {
        for (origin, kind) in [("https://mutable.top", 10000), ("https://plebsvszombies.cc", 3)] {
            let fixture = try BrowserSecurityFixture(origin: origin)
            defer { fixture.close() }
            try await fixture.load()
            let script = """
            return await nostr.signEvent({kind:kind,created_at:Math.floor(Date.now()/1000),
              tags:Array.from({length:2500},(_,index)=>['p',index.toString(16).padStart(64,'0')]),content:''});
            """
            for duration in [BrowserGrantDuration.once, .always] {
                async let requested = fixture.view.callAsyncJavaScript(script, arguments: ["kind": kind], in: nil, contentWorld: .page)
                try await fixture.waitUntil { fixture.browser.blockedRequests.first?.kind == kind }
                let blocked = try XCTUnwrap(fixture.browser.blockedRequests.first)
                XCTAssertTrue(fixture.signer.approvals.isEmpty || duration == .always)
                XCTAssertTrue(fixture.browser.canAllow(blocked))
                XCTAssertTrue(blocked.waiting)
                fixture.browser.allowBlockedRequest(blocked.id, duration: duration)
                let signed = try await requested as? [String: Any]
                XCTAssertEqual(signed?["kind"] as? Int, kind)
                XCTAssertEqual((signed?["tags"] as? [[String]])?.count, 2500)
                XCTAssertEqual(fixture.browser.actionGrants.map(\.kind), duration == .once ? [] : [kind])
            }
            XCTAssertFalse(fixture.browser.accountChangesAllowed)
            fixture.browser.setAccountChanges(false)
            XCTAssertTrue(fixture.browser.actionGrants.isEmpty)
        }
    }

    func testRelayBurstQueuesSeparatelyAndLeavesLoginAndPostingAvailable() async throws {
        let gate = BrowserRelaySettingsGate()
        let fixture = try BrowserSecurityFixture(origin: "https://jumble.social", relaySettingsProvider: { await gate.snapshot() })
        defer { gate.release(); fixture.close() }
        try await fixture.load()
        _ = try await fixture.view.evaluateJavaScript("""
        window.relayEvent = index => ({kind:22242,created_at:Math.floor(Date.now()/1000),
          tags:[['relay','wss://relay.example.invalid'],['challenge','burst-'+index]],content:''});
        window.relayBurst = Promise.all(Array.from({length:40}, (_,index) =>
          nostr.signEvent(window.relayEvent(index)).then(() => 1, () => 0)));
        true;
        """)
        try await fixture.waitUntil { gate.waiters.count == 1 }
        XCTAssertTrue(fixture.signer.approvals.isEmpty)
        let app = try await fixture.view.callAsyncJavaScript("""
        const key = await nostr.getPublicKey();
        const signed = await Promise.all([
          nostr.signEvent({kind:1,created_at:Math.floor(Date.now()/1000),tags:[],content:'draft'}),
          nostr.signEvent({kind:27235,created_at:Math.floor(Date.now()/1000),
            tags:[['u','https://jumble.social/login'],['method','POST']],content:''}),
          nostr.signEvent({kind:30078,created_at:Math.floor(Date.now()/1000),tags:[],content:'app data'})
        ]);
        return {key, kinds:signed.map(event => event.kind)};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(app?["key"] as? String, fixture.account.publicKey)
        XCTAssertEqual(app?["kinds"] as? [Int], [1, 27235, 30078])
        XCTAssertEqual(fixture.signer.approvals.count, 3)
        gate.release()
        let completed = try await fixture.view.callAsyncJavaScript(
            "return (await window.relayBurst).reduce((total,value) => total+value,0);",
            arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(completed as? Int, BrowserBridge.relayPendingLimit)
        // Exceed the old shared transport and signing budgets, then post again.
        _ = try await fixture.view.callAsyncJavaScript("""
        for (let batch=0;batch<5;batch++) {
          await Promise.all(Array.from({length:32},(_,index) =>
            nostr.signEvent(window.relayEvent(40+batch*32+index)).catch(() => null)));
        }
        return true;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(fixture.signer.approvals.filter { $0.event.kind == 22242 }.count, 120)
        let post = try await fixture.view.callAsyncJavaScript("""
        return (await nostr.signEvent({kind:1,created_at:Math.floor(Date.now()/1000),tags:[],content:'another draft'})).kind;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(post as? Int, 1)
        XCTAssertTrue(fixture.browser.blockedRequests.isEmpty)
    }

    func testMinimizeCancelsEveryQueuedRelayRequestAndLateSettingsCannotRestartIt() async throws {
        let gate = BrowserRelaySettingsGate()
        let fixture = try BrowserSecurityFixture(origin: "https://jumble.social", relaySettingsProvider: { await gate.snapshot() })
        defer { gate.release(); fixture.close() }
        try await fixture.load()
        _ = try await fixture.view.evaluateJavaScript("""
        window.queuedRelays = Promise.all(Array.from({length:12},(_,index) =>
          nostr.signEvent({kind:22242,created_at:Math.floor(Date.now()/1000),
            tags:[['relay','wss://relay.example.invalid'],['challenge','cancel-'+index]],content:''})
            .then(() => false, () => true)));
        true;
        """)
        try await fixture.waitUntil { gate.waiters.count == 1 }
        fixture.browser.setPresented(false)
        gate.release()
        let canceled = try await fixture.view.callAsyncJavaScript(
            "return (await window.queuedRelays).every(value => value);",
            arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(canceled as? Bool, true)
        fixture.browser.setPresented(true)
        XCTAssertTrue(fixture.signer.approvals.isEmpty)
        XCTAssertTrue(fixture.browser.blockedRequests.isEmpty)
    }

    func testMalformedAuthenticationIsVisibleInsteadOfHiddenAsRelayNoise() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        try await fixture.load()
        let result = try await fixture.view.callAsyncJavaScript("""
        try {
          await nostr.signEvent({kind:22242,created_at:Math.floor(Date.now()/1000),
            tags:[['domain','primal.net'],['challenge','private-nonce']],content:''});
          return false;
        } catch (_) { return true; }
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(result as? Bool, true)
        let blocked = try XCTUnwrap(fixture.browser.blockedRequests.first)
        XCTAssertFalse(blocked.canAllow)
        XCTAssertEqual(blocked.actionName, "Unrecognized sign-in request")
        XCTAssertFalse(blocked.reason.contains("private-nonce"))
        XCTAssertTrue(fixture.signer.approvals.isEmpty)
    }

    func testReadOnlyAccountsAreRejectedAndRemoteSignerAccountsCanBeSelected() throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        let readOnly = CloudAccount(entity: fixture.account.entity, insertInto: fixture.context)
        readOnly.publicKey = String(repeating: "b", count: 64)
        XCTAssertFalse(NostrBrowserModel.canUseAccount(readOnly))
        fixture.browser.selectAccount(readOnly)
        XCTAssertEqual(fixture.browser.accountPubkey, fixture.account.publicKey)
        let remote = CloudAccount(entity: fixture.account.entity, insertInto: fixture.context)
        remote.publicKey = String(repeating: "c", count: 64)
        remote.isNC = true
        XCTAssertTrue(NostrBrowserModel.canUseAccount(remote))
        fixture.browser.selectAccount(remote)
        XCTAssertEqual(fixture.browser.accountPubkey, remote.publicKey)
        fixture.browser.selectAccount(readOnly)
        XCTAssertEqual(fixture.browser.accountPubkey, remote.publicKey)
        fixture.context.delete(remote)
        XCTAssertFalse(NostrBrowserModel.canUseAccount(remote))
    }

    func testWebsiteChallengeLoginSignsAndCanBeAllowedWithoutRelayPermission() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://account.nostr.build")
        defer { fixture.close() }
        try await fixture.load()
        let script = """
        try {
            return (await nostr.signEvent({kind:22242,created_at:Math.floor(Date.now()/1000),
              tags:[['challenge','website-login'],['url','https://account.nostr.build']],content:''})).kind;
        } catch (_) { return 'denied'; }
        """
        let signed = try await fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(signed as? Int, 22242)
        XCTAssertTrue(fixture.browser.blockedRequests.isEmpty)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        fixture.browser.setWebsiteAuth(false)
        for duration in [BrowserGrantDuration.once, .always] {
            async let login = fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
            try await fixture.waitUntil { fixture.browser.blockedRequests.first?.kind == 22242 }
            let item = try XCTUnwrap(fixture.browser.blockedRequests.first)
            XCTAssertEqual(item.actionName, "Website sign-in")
            XCTAssertTrue(fixture.browser.canAllow(item))
            fixture.browser.allowBlockedRequest(item.id, duration: duration)
            let result = try await login
            XCTAssertEqual(result as? Int, 22242)
            XCTAssertEqual(fixture.browser.actionGrants.map(\.kind), duration == .once ? [] : [27235])
        }
        fixture.browser.setWebsiteAuth(false)
        XCTAssertTrue(fixture.browser.actionGrants.isEmpty)
        XCTAssertEqual(fixture.signer.approvals.count, 3)
    }

    func testConnectionApprovalResumesLoginAndAlwaysRemembersTheSite() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        let browser = fixture.browser
        let script = """
        window.loginOutcome = null;
        nostr.getPublicKey().then(key => { window.loginOutcome = key; }, () => { window.loginOutcome = 'denied'; });
        true;
        """
        for duration in [BrowserGrantDuration.once, .always] {
            try await fixture.load()
            XCTAssertFalse(browser.connected)
            _ = try await fixture.view.evaluateJavaScript(script)
            try await fixture.waitUntil { browser.blockedRequests.first?.kind == -1 }
            let blocked = try XCTUnwrap(browser.blockedRequests.first)
            XCTAssertTrue(browser.canAllow(blocked))
            browser.allowBlockedRequest(blocked.id, duration: duration)
            let deadline = Date().addingTimeInterval(3)
            var publicKey: String?
            while publicKey == nil && Date() < deadline {
                publicKey = try await fixture.view.evaluateJavaScript("window.loginOutcome") as? String
                if publicKey == nil { try await Task.sleep(nanoseconds: 25_000_000) }
            }
            XCTAssertEqual(publicKey, fixture.account.publicKey)
            XCTAssertTrue(browser.connected)
            XCTAssertTrue(browser.socialAllowed)
            XCTAssertFalse(browser.accountChangesAllowed)
        }
        try await fixture.load()
        XCTAssertTrue(browser.connected)
    }

    func testAllowOnceSignsOnlyThePendingRequest() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net")
        defer { fixture.close() }
        let browser = fixture.browser
        try await fixture.load()
        let script = """
        try {
            return (await nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[],content:''})).kind;
        } catch (_) { return 'denied'; }
        """
        async let first = fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { browser.blockedRequests.first?.kind == 3 }
        browser.allowBlockedRequest(try XCTUnwrap(browser.blockedRequests.first?.id), duration: .once)
        let firstResult = try await first as? Int
        XCTAssertEqual(firstResult, 3)
        XCTAssertTrue(browser.actionGrants.isEmpty)
        async let second = fixture.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { browser.blockedRequests.first?.kind == 3 }
        browser.declineBlockedRequest(try XCTUnwrap(browser.blockedRequests.first?.id))
        let secondResult = try await second as? String
        XCTAssertEqual(secondResult, "denied")
        XCTAssertEqual(fixture.signer.approvals.count, 1)
    }

    func testAllowOnceAfterTimeoutRequiresTheSameActionOnRetry() async throws {
        let fixture = try BrowserSecurityFixture(origin: "https://primal.net", approvalWaitSeconds: 1)
        defer { fixture.close() }
        let browser = fixture.browser
        try await fixture.load()
        let original = """
        try {
            return (await nostr.signEvent({kind:3,created_at:Math.floor(Date.now()/1000),tags:[['p','chosen']],content:''})).kind;
        } catch (_) { return 'denied'; }
        """
        async let expired = fixture.view.callAsyncJavaScript(original, arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { browser.blockedRequests.first?.waiting == false }
        let expiredResult = try await expired as? String
        XCTAssertEqual(expiredResult, "denied")
        browser.allowBlockedRequest(try XCTUnwrap(browser.blockedRequests.first?.id), duration: .once)
        let different = original.replacingOccurrences(of: "'chosen'", with: "'different'")
        async let unexpected = fixture.view.callAsyncJavaScript(different, arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { browser.blockedRequests.first?.kind == 3 }
        browser.declineBlockedRequest(try XCTUnwrap(browser.blockedRequests.first?.id))
        let unexpectedResult = try await unexpected as? String
        XCTAssertEqual(unexpectedResult, "denied")
        let retried = try await fixture.view.callAsyncJavaScript(original, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(retried as? Int, 3)
        XCTAssertEqual(fixture.signer.approvals.count, 1)
        XCTAssertTrue(browser.actionGrants.isEmpty)
    }

    func testAddressBarTrustRequiresAnEditAndStaysWithTheRequestedOrigin() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        let browser = fixture.browser
        try await fixture.load()
        XCTAssertFalse(browser.connected)
        browser.openAddress()
        XCTAssertFalse(browser.connected)

        browser.editAddress(fixture.baseURL.absoluteString)
        browser.openAddress()
        XCTAssertTrue(browser.connected)
        XCTAssertTrue(browser.socialAllowed)
        XCTAssertFalse(browser.accountChangesAllowed)
        XCTAssertFalse(browser.deletionsAllowed)
        XCTAssertFalse(browser.walletAllowed)

        browser.webView.stopLoading()
        let redirect = try XCTUnwrap(URL(string: "https://other.example.invalid"))
        browser.webView.loadHTMLString("<p>Different origin</p>", baseURL: redirect)
        try await fixture.waitUntil { browser.origin == BrowserSigningPolicy.origin(redirect) }
        XCTAssertFalse(browser.connected)
        XCTAssertFalse(browser.socialAllowed)
        browser.webView.loadHTMLString("<p>Back to the original origin</p>", baseURL: fixture.baseURL)
        try await fixture.waitUntil { browser.origin == BrowserSigningPolicy.origin(fixture.baseURL) }
        XCTAssertFalse(browser.connected)

        browser.setConnected(false)
        browser.setSocial(false)
        fixture.attach()
        browser.editAddress(fixture.baseURL.absoluteString)
        browser.openAddress()
        XCTAssertFalse(browser.connected)
        XCTAssertFalse(browser.socialAllowed)
    }

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
        async let pending = fixture.view.callAsyncJavaScript("try { \(script) } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { fixture.browser.blockedRequests.first?.kind == -1 }
        fixture.browser.declineBlockedRequest(try XCTUnwrap(fixture.browser.blockedRequests.first?.id))
        let denied = try await pending
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

    func testNewSiteCanConnectAndSignAppActionsInOneStep() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        try await fixture.load()
        XCTAssertFalse(fixture.browser.connected)
        fixture.browser.connectAndAllowAppActions()
        XCTAssertTrue(fixture.browser.connected)
        XCTAssertTrue(fixture.browser.socialAllowed)
        let now = Int64(Date().timeIntervalSince1970)
        let action = BrowserUnsignedEvent(created_at: now, kind: 4242, tags: [], content: "New app action")
        XCTAssertNotNil(BrowserSigningPolicy.approval(for: action, accountPubkey: fixture.account.publicKey,
            origin: try XCTUnwrap(fixture.browser.origin), connected: fixture.browser.connected,
            social: fixture.browser.socialAllowed, websiteAuth: fixture.browser.websiteAuthAllowed,
            uploads: fixture.browser.uploadsAllowed, relaySettings: [], now: now))
        XCTAssertTrue(fixture.browser.websiteAuthAllowed)
        XCTAssertFalse(fixture.browser.accountChangesAllowed)
        XCTAssertFalse(fixture.browser.deletionsAllowed)
        XCTAssertFalse(fixture.browser.walletAllowed)

        let reopened = NostrBrowserModel(preferences: fixture.preferences)
        defer { reopened.close() }
        reopened.selectAccount(fixture.account)
        reopened.open(fixture.baseURL)
        XCTAssertTrue(reopened.connected)
        XCTAssertTrue(reopened.socialAllowed)
        reopened.open(try XCTUnwrap(URL(string: "https://other.example.invalid")))
        XCTAssertFalse(reopened.connected)
        XCTAssertFalse(reopened.socialAllowed)
    }

    func testRealBridgeSharesOnlyExplicitlyConnectedIdentityAndApprovedEvents() async throws {
        let fixture = try BrowserSecurityFixture()
        defer { fixture.close() }
        try await fixture.load()
        XCTAssertFalse(fixture.browser.connected)
        XCTAssertFalse(fixture.browser.socialAllowed)
        XCTAssertFalse(fixture.browser.websiteAuthAllowed)
        XCTAssertFalse(fixture.browser.uploadsAllowed)
        async let connection = fixture.view.callAsyncJavaScript("try { await nostr.getPublicKey(); return false; } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        try await fixture.waitUntil { fixture.browser.blockedRequests.first?.kind == -1 }
        fixture.browser.declineBlockedRequest(try XCTUnwrap(fixture.browser.blockedRequests.first?.id))
        let denied = try await connection
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
        second.flagsSet = ["full_account"]
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

    init(origin: String = "https://security.example.invalid", approvalWaitSeconds: UInt64 = 120,
         relaySettingsProvider: @escaping @MainActor () async -> [BrowserRelaySetting] = { [] }) throws {
        baseURL = try XCTUnwrap(URL(string: origin))
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        account = CloudAccount(entity: try XCTUnwrap(model.entitiesByName["CloudAccount"]), insertInto: context)
        account.publicKey = String(repeating: "a", count: 64)
        account.name = "Browser boundary test"
        account.flagsSet = ["full_account"]
        preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        browser = NostrBrowserModel(relaySettingsProvider: relaySettingsProvider, signer: signer, preferences: preferences, approvalWaitSeconds: approvalWaitSeconds)
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

    func load(marker: String = UUID().uuidString) async throws {
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
private final class BrowserRelaySettingsGate {
    var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func snapshot() async -> [BrowserRelaySetting] {
        if !released {
            await withCheckedContinuation { waiters.append($0) }
        }
        return [BrowserRelaySetting(url: "wss://relay.example.invalid", auth: true)]
    }

    func release() {
        released = true
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume() }
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
