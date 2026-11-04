import XCTest
import WebKit
@testable import Nostur

@MainActor
final class BrowserBridgeTests: XCTestCase {
    private func page(_ html: String = "<html><body>Bridge test</body></html>") async throws -> (WKWebView, BrowserBridgeHarness) {
        let harness = BrowserBridgeHarness()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        BrowserBridge.install(in: config.userContentController, handler: harness)
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = harness
        let loaded = expectation(description: "Local bridge page loaded")
        harness.loaded = { loaded.fulfill() }
        view.loadHTMLString(html, baseURL: URL(string: "https://example.test"))
        await fulfillment(of: [loaded], timeout: 10)
        return (view, harness)
    }

    func testNIP07PromisesAndNativeHandlerIsolation() async throws {
        let (view, harness) = try await page()
        defer { view.configuration.userContentController.removeScriptMessageHandler(forName: "nostur", contentWorld: BrowserBridge.world) }
        let result = try await view.callAsyncJavaScript("""
        const key = await window.nostr.getPublicKey();
        const signed = await window.nostr.signEvent({kind: 1, created_at: 1800000000, tags: [], content: 'hello', pubkey: 'attacker', privateKey: 'export please'});
        let rejected = false;
        try { await window.nostr.signEvent({kind: 0, created_at: 1800000000, tags: [], content: ''}); } catch (_) { rejected = true; }
        return {key, id: signed.id, rejected, capabilities: Object.keys(window.nostr).sort().join(','),
                nativeHandler: typeof window.webkit?.messageHandlers?.nostur,
                nativeToken: typeof globalThis.__nosturDocumentToken};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["key"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(result?["id"] as? String, "signed-test-event")
        XCTAssertEqual(result?["rejected"] as? Bool, true)
        XCTAssertEqual(result?["capabilities"] as? String, "getPublicKey,signEvent")
        XCTAssertEqual(result?["nativeHandler"] as? String, "undefined")
        XCTAssertEqual(result?["nativeToken"] as? String, "undefined")
        XCTAssertTrue(harness.mainFramesOnly)
        XCTAssertEqual(harness.requests.count, 3)
        XCTAssertTrue(harness.requests.allSatisfy { $0.documentToken == harness.token })
    }

    func testEmbeddedFramesAndForgedEventsCannotReachNativeHandler() async throws {
        let (view, harness) = try await page("<html><body><iframe srcdoc='<p>Embedded page</p>'></iframe></body></html>")
        defer { view.configuration.userContentController.removeScriptMessageHandler(forName: "nostur", contentWorld: BrowserBridge.world) }
        let result = try await view.callAsyncJavaScript("""
        const request = JSON.stringify({channel:'nostur.request.v1', id:'forged', method:'getPublicKey', event:null});
        window.dispatchEvent(new MessageEvent('message', {source:window, origin:location.origin, data:request}));
        const iframe = document.querySelector('iframe');
        iframe.contentWindow.eval('parent.postMessage(' + JSON.stringify(request) + ', "*")');
        await new Promise(resolve => setTimeout(resolve, 150));
        return {provider:typeof iframe.contentWindow.nostr, handler:typeof iframe.contentWindow.webkit?.messageHandlers?.nostur};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["provider"] as? String, "undefined")
        XCTAssertEqual(result?["handler"] as? String, "undefined")
        XCTAssertEqual(harness.requests.count, 0)
    }

    func testUnsupportedMethodsAndOversizedPayloadsDoNotReachNativeHandler() async throws {
        let (view, harness) = try await page()
        defer { view.configuration.userContentController.removeScriptMessageHandler(forName: "nostur", contentWorld: BrowserBridge.world) }
        _ = try await view.callAsyncJavaScript("""
        window.postMessage(JSON.stringify({channel:'nostur.request.v1', id:'export', method:'getPrivateKey', event:null}), location.origin);
        let failed = false;
        try { await window.nostr.signEvent({kind:1, created_at:1800000000, tags:[], content:'x'.repeat(200000)}); } catch (_) { failed = true; }
        await new Promise(resolve => setTimeout(resolve, 150));
        return failed;
        """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(harness.requests.count, 0)
    }

    func testNativePacketDecoderRejectsUnknownCapabilitiesAndFields() throws {
        let token = UUID().uuidString
        func packet(_ method: String, extras: [String: Any] = [:]) throws -> String {
            var object: [String: Any] = ["documentToken": token, "method": method, "event": NSNull()]
            object.merge(extras) { _, new in new }
            return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        XCTAssertNotNil(BrowserBridgeRequest.decode(try packet("getPublicKey")))
        for method in ["getPrivateKey", "getAccounts", "getRelays", "nip04.decrypt", "nip44.decrypt", "eval", "readFile", "publishEvent"] {
            XCTAssertNil(BrowserBridgeRequest.decode(try packet(method)))
        }
        XCTAssertNil(BrowserBridgeRequest.decode(try packet("getPublicKey", extras: ["accountPubkey": "other-account"])))
        XCTAssertNil(BrowserBridgeRequest.decode(["documentToken": token, "method": "getPublicKey"]))
        XCTAssertNil(BrowserBridgeRequest.decode(String(repeating: "x", count: 131073)))
        XCTAssertNil(BrowserBridgeRequest.decode(try packet("getPublicKey", extras: ["documentToken": "not-a-document-token"])))
    }
}

@MainActor
private final class BrowserBridgeHarness: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let token = UUID().uuidString
    var loaded: (() -> Void)?
    var mainFramesOnly = true
    var requests: [BrowserBridgeRequest] = []

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { BrowserBridge.activate(webView, token: token) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?(); loaded = nil }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        mainFramesOnly = mainFramesOnly && message.frameInfo.isMainFrame
        guard let request = BrowserBridgeRequest.decode(message.body), request.documentToken == token else {
            replyHandler(nil, "Invalid request"); return
        }
        requests.append(request)
        if request.method == .getPublicKey {
            replyHandler(String(data: try! JSONEncoder().encode(String(repeating: "a", count: 64)), encoding: .utf8), nil)
        } else if request.event?.kind == 1 {
            replyHandler(String(data: try! JSONEncoder().encode(["id": "signed-test-event"]), encoding: .utf8), nil)
        } else {
            replyHandler(nil, "Blocked by test signer")
        }
    }
}
