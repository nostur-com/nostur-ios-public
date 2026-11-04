import SwiftUI
import WebKit

/// WebKit owns its message handler. Keep the reference back to the browser weak.
@MainActor
private final class BrowserMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var browser: NostrBrowserModel?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let browser else { replyHandler(nil, "Browser closed."); return }
        browser.receive(message, reply: replyHandler)
    }
}

struct BrowserActivity: Identifiable {
    let id = UUID()
    let date = Date()
    let site: String
    let detail: String
    let blocked: Bool
}

@MainActor
final class NostrBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView!
    @Published private(set) var isHome = true
    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var loading = false
    @Published private(set) var accountPubkey = ""
    @Published private(set) var accountName = ""
    @Published private(set) var accountPictureURL: URL?
    @Published private(set) var activity: [BrowserActivity] = []
    @Published private(set) var blockedRequests: [BrowserBlockedRequest] = []
    @Published var blockedRequestsShown = false
    @Published private(set) var grantFeedback: String?
    var openSettingsAfterBlockedRequests = false
    @Published var notice: String?
    @Published var address = ""
    @Published var settingsShown = false
    @Published var controlsExpanded = true
    @Published private(set) var favorites: Set<String>
    private let preferences: UserDefaults
    private let approvalWaitSeconds: UInt64

    private var observations: [NSKeyValueObservation] = []
    private struct PendingRequest {
        let reply: (Any?, String?) -> Void
        let scope: BrowserRequestScope
        let event: BrowserUnsignedEvent
    }
    private var pending: [UUID: PendingRequest] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private let signer: any BrowserEventSigning
    private var documentToken: String?
    private var documentReady = false
    private(set) var isPresented = false
    private let relaySettingsProvider: @MainActor () async -> [BrowserRelaySetting]
    private var requestTimes: [Date] = []
    private var signatureTimes: [Date] = []
    private var previousPanTranslation: CGFloat = 0
    private var scrollTravel: CGFloat = 0

    init(relaySettingsProvider: @escaping @MainActor () async -> [BrowserRelaySetting] = { await BrowserRelaySettings.snapshot() },
         signer: (any BrowserEventSigning)? = nil, preferences: UserDefaults = .standard, approvalWaitSeconds: UInt64 = 120) {
        self.relaySettingsProvider = relaySettingsProvider
        self.preferences = preferences
        self.approvalWaitSeconds = min(120, max(1, approvalWaitSeconds))
        self.favorites = Set(preferences.stringArray(forKey: "browser.favorites") ?? [])
        self.signer = signer ?? NativeBrowserEventSigner()
        super.init()
        replaceWebView()
    }

    var origin: String? { BrowserSigningPolicy.origin(currentURL) }
    private func preferenceKey(_ capability: String) -> String? {
        guard let origin, !accountPubkey.isEmpty else { return nil }
        return "browser.\(capability).\(accountPubkey).\(origin)"
    }
    var connected: Bool {
        guard let origin, let key = preferenceKey("connected") else { return false }
        return preferences.object(forKey: key) as? Bool ?? BrowserSiteDefaults.forOrigin(origin).connected
    }
    var socialAllowed: Bool {
        guard let origin, let key = preferenceKey("social") else { return false }
        return preferences.object(forKey: key) as? Bool ?? BrowserSigningPolicy.socialDefault(origin)
    }

    var websiteAuthAllowed: Bool {
        guard let origin, let key = preferenceKey("websiteAuth") else { return false }
        return preferences.object(forKey: key) as? Bool ?? BrowserSiteDefaults.forOrigin(origin).websiteAuth
    }
    var uploadsAllowed: Bool {
        guard let origin, let key = preferenceKey("uploads") else { return false }
        return preferences.object(forKey: key) as? Bool ?? BrowserSiteDefaults.forOrigin(origin).uploads
    }
    func setWebsiteAuth(_ enabled: Bool) { setCapability("websiteAuth", enabled: enabled) }
    func setUploads(_ enabled: Bool) { setCapability("uploads", enabled: enabled) }
    private func setCapability(_ name: String, enabled: Bool) {
        guard let key = preferenceKey(name) else { return }
        preferences.set(enabled, forKey: key)
        if !enabled, let origin {
            let kind = name == "websiteAuth" ? 27235 : 24242
            BrowserActionPermissions(preferences: preferences).revoke(kind: kind, account: accountPubkey, origin: origin)
        }
        cancelPending()
        objectWillChange.send()
    }

    func setConnected(_ enabled: Bool) {
        guard let key = preferenceKey("connected") else { return }
        preferences.set(enabled, forKey: key)
        resetSession()
        guard !enabled, let host = currentURL?.host else { return }
        let store = webView.configuration.websiteDataStore
        // Revoke signing immediately, then clear this website's login off the
        // UI path. Other websites and accounts keep their sessions.
        Task { @MainActor in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await store.dataRecords(ofTypes: types)
            let matches = records.filter {
                host == $0.displayName || host.hasSuffix("." + $0.displayName)
                    || $0.displayName.hasSuffix("." + host)
            }
            await store.removeData(ofTypes: types, for: matches)
        }
    }

    func setSocial(_ enabled: Bool) {
        guard let key = preferenceKey("social") else { return }
        preferences.set(enabled, forKey: key)
        if !enabled, let origin {
            let permissions = BrowserActionPermissions(preferences: preferences)
            for grant in permissions.grants(account: accountPubkey, origin: origin) where BrowserSigningPolicy.socialKinds.contains(grant.kind) {
                permissions.revoke(kind: grant.kind, account: accountPubkey, origin: origin)
            }
        }
        cancelPending()
        objectWillChange.send()
    }

    func selectAccount(_ account: CloudAccount) {
        guard !account.isDeleted, account.managedObjectContext != nil else { return }
        guard accountPubkey != account.publicKey else { return }
        accountPubkey = account.publicKey
        accountName = account.anyName
        accountPictureURL = account.pictureUrl
        resetSession()
    }

    private func resetSession() {
        let url = isHome ? nil : currentURL
        replaceWebView()
        if let url { open(url) }
    }

    private func replaceWebView() {
        documentReady = false
        documentToken = nil
        cancelPending()
        webView?.stopLoading()
        webView?.scrollView.panGestureRecognizer.removeTarget(self, action: #selector(browserPanChanged(_:)))
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "nostur", contentWorld: BrowserBridge.world)
        observations.removeAll()
        let config = WKWebViewConfiguration()
        // Persistent, isolated website profiles retain logins when closing or
        // changing accounts. Private keys never enter this store or JavaScript.
        config.websiteDataStore = BrowserWebsiteStorage.shared.store(account: accountPubkey, preferences: preferences)
        config.allowsInlineMediaPlayback = true
        let handler = BrowserMessageHandler()
        handler.browser = self
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        BrowserBridge.install(in: config.userContentController, handler: handler)
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.scrollView.panGestureRecognizer.addTarget(self, action: #selector(browserPanChanged(_:)))
        view.allowsBackForwardNavigationGestures = true
        webView = view
        observations = [view.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async {
                guard let self, self.webView === view else { return }
                self.loading = view.isLoading
                self.canGoBack = view.canGoBack
                self.canGoForward = view.canGoForward
            }
        }]
    }

    func openAddress() {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input.contains("://") ? input : "https://" + input),
              BrowserSigningPolicy.origin(url) != nil else {
            notice = String(localized: "Enter a valid HTTPS address."); return
        }
        open(url)
    }

    func open(_ url: URL) {
        guard BrowserSigningPolicy.origin(url) != nil else { return }
        cancelPending()
        documentReady = false
        documentToken = nil
        notice = nil
        isHome = false
        controlsExpanded = false
        currentURL = url
        address = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func home() {
        documentReady = false
        documentToken = nil
        cancelPending()
        webView.stopLoading()
        // Unload the site so hidden pages cannot continue requesting signatures.
        webView.loadHTMLString("", baseURL: nil)
        currentURL = nil
        address = ""
        notice = nil
        isHome = true
        controlsExpanded = true
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            cancelPending()
            settingsShown = false
            blockedRequestsShown = false
            notice = nil
        }
    }

    func close() {
        setPresented(false)
        home()
        webView.scrollView.panGestureRecognizer.removeTarget(self, action: #selector(browserPanChanged(_:)))
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nostur", contentWorld: BrowserBridge.world)
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        preferences.set(Array(favorites), forKey: "browser.favorites")
    }

    @objc private func browserPanChanged(_ pan: UIPanGestureRecognizer) {
        guard pan.view === webView.scrollView else { return }
        if pan.state == .began {
            previousPanTranslation = 0
            scrollTravel = 0
        }
        guard pan.state == .changed, !isHome, !loading, !webView.scrollView.isZooming else { return }
        let translation = pan.translation(in: pan.view)
        defer { previousPanTranslation = translation.y }
        guard abs(translation.y) > abs(translation.x) else { return }
        // Use the finger's movement, not content offsets: resizing the viewport
        // or rubber-banding must not cause the controls to oscillate. Observe
        // WebKit's existing gesture without taking over its scroll delegate.
        let delta = previousPanTranslation - translation.y
        if delta * scrollTravel < 0 { scrollTravel = 0 }
        scrollTravel += delta
        if scrollTravel > 48, controlsExpanded { controlsExpanded = false; scrollTravel = 0 }
        if scrollTravel < -24, !controlsExpanded { controlsExpanded = true; scrollTravel = 0 }
    }

    var actionGrants: [BrowserActionGrant] {
        guard let origin else { return [] }
        return BrowserActionPermissions(preferences: preferences).grants(account: accountPubkey, origin: origin)
    }
    private var allowedKinds: Set<Int> { Set(actionGrants.map(\.kind)) }

    func canAllow(_ item: BrowserBlockedRequest) -> Bool {
        item.canAllow && currentScope() == item.scope
    }

    func allowBlockedRequest(_ id: UUID, duration: BrowserGrantDuration) {
        guard let item = blockedRequests.first(where: { $0.id == id }), canAllow(item) else { return }
        BrowserActionPermissions(preferences: preferences).allow(kind: item.kind, account: item.scope.accountPubkey,
                                                                origin: item.scope.origin, duration: duration)
        let retryIDs = blockedRequests.filter { $0.kind == item.kind && $0.scope == item.scope && $0.waiting }.map(\.id)
        blockedRequests.removeAll { $0.kind == item.kind && $0.scope == item.scope }
        grantFeedback = retryIDs.isEmpty ? String(localized: "Permission saved. Retry the action in the app.") : String(localized: "Permission saved. This action is now allowed.")
        for id in retryIDs {
            armTimeout(id, seconds: 15)
            authorizeAndSign(id, relaySettings: [])
        }
    }

    func declineBlockedRequest(_ id: UUID) {
        if let request = takePending(id) { request.reply(nil, "Nostur declined this request.") }
        blockedRequests.removeAll { $0.id == id }
    }

    func revokeAction(_ kind: Int) {
        guard let origin else { return }
        BrowserActionPermissions(preferences: preferences).revoke(kind: kind, account: accountPubkey, origin: origin)
        cancelPending()
        objectWillChange.send()
    }

    private func armTimeout(_ id: UUID, seconds: UInt64) {
        timeouts.removeValue(forKey: id)?.cancel()
        timeouts[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self else { return }
            if self.blockedRequests.contains(where: { $0.id == id }) {
                self.takePending(id)?.reply(nil, "Request expired. Retry the action after allowing it.")
            } else { self.reject(id, reason: String(localized: "Signing request expired.")) }
        }
    }

    private func takePending(_ id: UUID) -> PendingRequest? {
        timeouts.removeValue(forKey: id)?.cancel()
        signer.cancel(id)
        if let index = blockedRequests.firstIndex(where: { $0.id == id }) { blockedRequests[index].waiting = false }
        return pending.removeValue(forKey: id)
    }

    private func cancelPending() {
        blockedRequests.removeAll()
        grantFeedback = nil
        for id in Array(pending.keys) {
            takePending(id)?.reply(nil, "Browser session changed.")
        }
    }

    private func record(_ detail: String, blocked: Bool, showNotice: Bool = true) {
        activity.insert(BrowserActivity(site: origin ?? "", detail: detail, blocked: blocked), at: 0)
        activity = Array(activity.prefix(30))
        if blocked && showNotice { notice = detail }
    }

    private func currentScope() -> BrowserRequestScope? {
        guard isPresented, webView.window != nil, !isHome, documentReady,
              let documentToken, let origin, BrowserSigningPolicy.origin(webView.url) == origin,
              connected, UIApplication.shared.applicationState == .active,
              BrowserSignedEvent.isHex(accountPubkey, count: 64),
              AccountsState.shared.accounts.contains(where: { !$0.isDeleted && $0.publicKey == accountPubkey }) else { return nil }
        return BrowserRequestScope(documentToken: documentToken, origin: origin, accountPubkey: accountPubkey)
    }

    func receive(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        let now = Date()
        requestTimes.removeAll { now.timeIntervalSince($0) >= 60 }
        guard requestTimes.count < 120 else { reply(nil, "Nostur request limit reached."); return }
        requestTimes.append(now)
        // Security origin and frame identity come from WebKit, not the page.
        let securityOrigin = message.frameInfo.securityOrigin
        let frameOrigin = BrowserSigningPolicy.origin(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
        let decodedRequest = BrowserBridgeRequest.decode(message.body)
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let request = decodedRequest,
              let scope = currentScope(), frameOrigin == scope.origin,
              request.documentToken == scope.documentToken else {
            if isPresented && !connected && decodedRequest?.event?.kind != 22242,
               message.webView === webView, message.frameInfo.isMainFrame, let documentToken,
               decodedRequest?.documentToken == documentToken, let origin, frameOrigin == origin {
                let blockedScope = BrowserRequestScope(documentToken: documentToken, origin: origin, accountPubkey: accountPubkey)
                if !blockedRequests.contains(where: { $0.kind == -1 && $0.scope == blockedScope }) {
                    let reason = String(localized: "Use Website controls to connect this site to your Nostur account.")
                    blockedRequests.insert(BrowserBlockedRequest(id: UUID(), scope: blockedScope, kind: -1,
                        reason: reason, canAllow: false, waiting: false), at: 0)
                    blockedRequests = Array(blockedRequests.prefix(30))
                    record(reason, blocked: true, showNotice: false)
                }
            }
            reply(nil, "Nostur signing is unavailable for this page."); return
        }
        if request.method == .getPublicKey {
            reply(Self.jsonString(scope.accountPubkey), nil)
            return
        }
        guard let event = request.event, pending.count < 4 else { reply(nil, "Invalid request or too many pending requests."); return }
        let id = UUID()
        pending[id] = PendingRequest(reply: reply, scope: scope, event: event)
        armTimeout(id, seconds: 15)
        let provider = relaySettingsProvider
        Task { @MainActor [weak self] in
            let settings = event.kind == 22242 ? await provider() : []
            self?.authorizeAndSign(id, relaySettings: settings)
        }
    }

    private func reject(_ id: UUID, reason: String) {
        guard let request = takePending(id) else { return }
        // Relays commonly challenge every connected client. Declining one is
        // routine when native relay authentication is off; retain diagnostics
        // without interrupting browsing with a banner.
        record(reason, blocked: true, showNotice: false)
        if request.event.kind != 22242, currentScope() == request.scope,
           !blockedRequests.contains(where: { $0.id == id }) {
            blockedRequests.insert(BrowserBlockedRequest(id: id, scope: request.scope, kind: request.event.kind,
                reason: reason, canAllow: false, waiting: false), at: 0)
            blockedRequests = Array(blockedRequests.prefix(30))
        }
        request.reply(nil, "Nostur declined this request.")
    }

    private func authorizeAndSign(_ id: UUID, relaySettings: [BrowserRelaySetting]) {
        guard let request = pending[id] else { return }
        guard currentScope() == request.scope else { reject(id, reason: String(localized: "Browser session changed.")); return }
        let event = request.event
        if let reason = BrowserSigningPolicy.rejection(for: event, origin: request.scope.origin, social: socialAllowed,
                                                       websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed, relaySettings: relaySettings, allowedKinds: allowedKinds) {
            let grantable = BrowserSigningPolicy.canGrant(event.kind) && BrowserSigningPolicy.approval(
                for: event, accountPubkey: request.scope.accountPubkey, origin: request.scope.origin, connected: connected,
                social: socialAllowed, websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed,
                relaySettings: relaySettings, allowedKinds: [event.kind]) != nil
            if grantable {
                if !blockedRequests.contains(where: { $0.id == id }) {
                    blockedRequests.insert(BrowserBlockedRequest(id: id, scope: request.scope, kind: event.kind,
                        reason: reason, canAllow: true, waiting: true), at: 0)
                    record(reason, blocked: true, showNotice: false)
                    armTimeout(id, seconds: approvalWaitSeconds)
                }
            } else { reject(id, reason: reason) }
            return
        }
        let now = Date()
        signatureTimes.removeAll { now.timeIntervalSince($0) >= 60 }
        guard signatureTimes.count < 20 else {
            reject(id, reason: String(localized: "Signing limit reached. Try again in a minute.")); return
        }
        guard let approval = BrowserSigningPolicy.approval(for: event, accountPubkey: request.scope.accountPubkey,
                                                          origin: request.scope.origin, connected: connected, social: socialAllowed,
                                                          websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed, relaySettings: relaySettings, allowedKinds: allowedKinds) else {
            reject(id, reason: String(localized: "This request is not authorized.")); return
        }
        signatureTimes.append(now)
        signer.sign(approval, requestID: id) { [weak self] result in self?.finish(id, result: result) }
    }

    private func finish(_ id: UUID, result: Result<BrowserSignedEvent, BrowserSigningFailure>) {
        guard let request = pending[id] else { return }
        let provider = relaySettingsProvider
        Task { @MainActor [weak self] in
            // Recheck relay permission after a remote signer/queue delay too.
            let settings = request.event.kind == 22242 ? await provider() : []
            self?.deliver(id, result: result, relaySettings: settings)
        }
    }

    private func deliver(_ id: UUID, result: Result<BrowserSignedEvent, BrowserSigningFailure>, relaySettings: [BrowserRelaySetting]) {
        guard let request = pending[id] else { return }
        guard currentScope() == request.scope,
              BrowserSigningPolicy.rejection(for: request.event, origin: request.scope.origin, social: socialAllowed,
                                             websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed, relaySettings: relaySettings, allowedKinds: allowedKinds) == nil else {
            reject(id, reason: String(localized: "Browser permissions or session changed.")); return
        }
        switch result {
        case .success(let signed):
            guard signed.matches(request.event, accountPubkey: request.scope.accountPubkey), let json = Self.jsonString(signed) else {
                reject(id, reason: String(localized: "Signing failed.")); return
            }
            guard let response = takePending(id) else { return }
            let name = BrowserEventDescription.name(for: request.event.kind)
            let kind = String(request.event.kind)
            record(String(localized: "Signed: \(name) (kind \(kind))."), blocked: false)
            blockedRequests.removeAll { $0.id == id }
            response.reply(json, nil)
        case .failure:
            reject(id, reason: String(localized: "Signing failed or timed out."))
        }
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        guard BrowserSigningPolicy.origin(url) != nil else {
            if navigationAction.targetFrame?.isMainFrame != false {
                notice = String(localized: "Only HTTPS pages can open in this browser.")
            }
            decisionHandler(.cancel); return
        }
        if navigationAction.targetFrame?.isMainFrame == true { cancelPending() }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        documentReady = false
        documentToken = nil
        cancelPending()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView, !isHome, BrowserSigningPolicy.origin(webView.url) != nil else { return }
        cancelPending()
        documentReady = true
        let token = UUID().uuidString
        documentToken = token
        currentURL = webView.url
        address = webView.url?.absoluteString ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        BrowserBridge.activate(webView, token: token)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        notice = String(localized: "This page could not load. Check the address or try reloading.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        documentReady = false
        documentToken = nil
        cancelPending()
        notice = String(localized: "The page stopped. Reload to continue.")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if isPresented, navigationAction.sourceFrame.isMainFrame, let url = navigationAction.request.url { open(url) }
        return nil
    }
}

