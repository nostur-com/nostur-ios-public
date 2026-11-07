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
    let id: UUID
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
    @Published private(set) var address = ""
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
    private struct PendingConnection {
        let request: BrowserBridgeRequest
        let reply: (Any?, String?) -> Void
    }
    private var pending: [UUID: PendingRequest] = [:]
    private var pendingConnection: [PendingConnection] = []
    private var oneTimeApprovals: Set<UUID> = []
    private var oneTimeRetries: [BrowserBlockedRequest] = []
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
    private var addressEdited = false
    // Automatic permissions apply only to this visit. Explicit settings
    // still win and remain saved for their account and origin.
    private var trustedVisit: (origin: String, account: String)?
    private var temporaryConnection: BrowserRequestScope?
    private var postLinkTask: Task<Void, Never>?

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
    private var hasTrustedVisit: Bool {
        guard let trustedVisit else { return false }
        return trustedVisit.origin == origin && trustedVisit.account == accountPubkey
    }
    private func preferenceKey(_ capability: String) -> String? {
        guard let origin, !accountPubkey.isEmpty else { return nil }
        return "browser.\(capability).\(accountPubkey).\(origin)"
    }
    var connected: Bool {
        guard let origin, let key = preferenceKey("connected") else { return false }
        if hasTemporaryConnection { return true }
        return preferences.object(forKey: key) as? Bool ?? (hasTrustedVisit || BrowserSiteDefaults.forOrigin(origin).connected)
    }
    private var hasTemporaryConnection: Bool {
        guard let temporaryConnection else { return false }
        return temporaryConnection.origin == origin && temporaryConnection.accountPubkey == accountPubkey
    }
    var socialAllowed: Bool {
        guard let origin, let key = preferenceKey("social") else { return false }
        return preferences.object(forKey: key) as? Bool ?? (hasTemporaryConnection || hasTrustedVisit || BrowserSigningPolicy.socialDefault(origin))
    }

    var websiteAuthAllowed: Bool {
        guard connected, let key = preferenceKey("websiteAuth") else { return false }
        return preferences.object(forKey: key) as? Bool ?? true
    }
    // Uploads follow App actions, including existing social overrides. The old
    // independent uploads preference is no longer consulted.
    var uploadsAllowed: Bool { socialAllowed }
    var accountChangesAllowed: Bool { capability("accountChanges") }
    var deletionsAllowed: Bool { capability("deletions") }
    var walletAllowed: Bool { capability("wallet") }
    private func capability(_ name: String) -> Bool {
        guard let key = preferenceKey(name) else { return false }
        return preferences.bool(forKey: key)
    }
    func setWebsiteAuth(_ enabled: Bool) { setCapability("websiteAuth", enabled: enabled) }
    func setAccountChanges(_ enabled: Bool) { setCapability("accountChanges", enabled: enabled) }
    func setDeletions(_ enabled: Bool) { setCapability("deletions", enabled: enabled) }
    func setWallet(_ enabled: Bool) { setCapability("wallet", enabled: enabled) }
    private func setCapability(_ name: String, enabled: Bool) {
        guard let key = preferenceKey(name) else { return }
        preferences.set(enabled, forKey: key)
        if !enabled, let origin {
            let permissions = BrowserActionPermissions(preferences: preferences)
            for grant in permissions.grants(account: accountPubkey, origin: origin) {
                let matches = (name == "websiteAuth" && grant.kind == 27235 && grant.destination == nil)
                    || (name == "accountChanges" && BrowserSigningPolicy.isAccountChange(grant.kind))
                    || (name == "deletions" && BrowserSigningPolicy.isDeletion(grant.kind))
                    || (name == "wallet" && BrowserSigningPolicy.nwcKinds.contains(grant.kind))
                if matches { permissions.revoke(kind: grant.kind, account: accountPubkey, origin: origin) }
            }
        }
        cancelPending()
        objectWillChange.send()
    }

    func connectAndAllowAppActions() {
        guard !connected, let key = preferenceKey("social") else { return }
        preferences.set(true, forKey: key)
        setConnected(true)
    }

    func setConnected(_ enabled: Bool) {
        guard let key = preferenceKey("connected") else { return }
        temporaryConnection = nil
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
            for grant in permissions.grants(account: accountPubkey, origin: origin) where BrowserSigningPolicy.isAppAction(grant.kind) || grant.kind == 24242 {
                permissions.revoke(kind: grant.kind, account: accountPubkey, origin: origin)
            }
        }
        cancelPending()
        objectWillChange.send()
    }

    func selectAccount(_ account: CloudAccount) {
        guard !account.isDeleted, account.managedObjectContext != nil else { return }
        guard accountPubkey != account.publicKey else { return }
        postLinkTask?.cancel()
        postLinkTask = nil
        trustedVisit = nil
        temporaryConnection = nil
        accountPubkey = account.publicKey
        accountName = account.anyName
        accountPictureURL = account.pictureUrl
        resetSession()
    }

    private func resetSession() {
        let url = isHome ? nil : currentURL
        replaceWebView()
        if let url { load(url) }
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

    func editAddress(_ value: String) {
        address = value
        addressEdited = true
    }

    func openAddress() {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input.contains("://") ? input : "https://" + input),
              BrowserSigningPolicy.origin(url) != nil else {
            notice = String(localized: "Enter a valid HTTPS address."); return
        }
        if addressEdited {
            open(url, trusted: true)
        } else {
            load(url)
        }
    }

    func open(_ url: URL) {
        open(url, trusted: false)
    }

    private func open(_ url: URL, trusted: Bool) {
        guard let origin = BrowserSigningPolicy.origin(url) else { return }
        temporaryConnection = nil
        trustedVisit = trusted && !accountPubkey.isEmpty ? (origin, accountPubkey) : nil
        load(url)
    }

    func openPostLink(_ url: URL, source: BrowserPostSource?) {
        guard let source, followsPostAuthor(source.pubkey) else {
            open(url)
            return
        }
        let selectedAccount = accountPubkey
        postLinkTask?.cancel()
        postLinkTask = Task { [weak self] in
            let verified = await source.verifiesLink(url)
            guard let self, !Task.isCancelled, self.accountPubkey == selectedAccount else { return }
            self.open(url, trusted: verified && self.followsPostAuthor(source.pubkey))
        }
    }

    private func followsPostAuthor(_ pubkey: String) -> Bool {
        guard !blocks().contains(pubkey),
              let account = AccountsState.shared.accounts.first(where: { !$0.isDeleted && $0.publicKey == accountPubkey }) else { return false }
        return account.followingPubkeys.contains(pubkey) || account.privateFollowingPubkeys.contains(pubkey)
    }

    private func load(_ url: URL) {
        postLinkTask?.cancel()
        postLinkTask = nil
        cancelPending()
        documentReady = false
        documentToken = nil
        notice = nil
        isHome = false
        controlsExpanded = false
        currentURL = url
        address = url.absoluteString
        addressEdited = false
        webView.load(URLRequest(url: url))
    }

    func home() {
        postLinkTask?.cancel()
        postLinkTask = nil
        trustedVisit = nil
        temporaryConnection = nil
        documentReady = false
        documentToken = nil
        cancelPending()
        webView.stopLoading()
        // Unload the site so hidden pages cannot continue requesting signatures.
        webView.loadHTMLString("", baseURL: nil)
        currentURL = nil
        address = ""
        addressEdited = false
        notice = nil
        isHome = true
        controlsExpanded = true
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !presented {
            postLinkTask?.cancel()
            postLinkTask = nil
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
    private var allowedKinds: Set<Int> { Set(actionGrants.filter { $0.destination == nil }.map(\.kind)) }
    private var httpDestinations: Set<String> { Set(actionGrants.compactMap(\.destination)) }

    func canAllow(_ item: BrowserBlockedRequest) -> Bool {
        guard item.canAllow else { return false }
        return item.kind == -1 ? !connected && documentScope() == item.scope : currentScope() == item.scope
    }

    func allowBlockedRequest(_ id: UUID, duration: BrowserGrantDuration) {
        guard let item = blockedRequests.first(where: { $0.id == id }), canAllow(item) else { return }
        if item.kind == -1 {
            allowConnection(item, duration: duration)
            return
        }
        if duration == .once {
            blockedRequests.removeAll { $0.id == id }
            if let request = pending[id], signingApproval(for: request, relaySettings: [], allowOnce: true) != nil {
                oneTimeApprovals.insert(id)
                armTimeout(id, seconds: 15)
                authorizeAndSign(id, relaySettings: [])
            } else {
                takePending(id)?.reply(nil, "Request expired. Retry the action to use this permission.")
                oneTimeRetries.removeAll { $0.kind == item.kind && $0.destination == item.destination }
                oneTimeRetries.append(item)
                grantFeedback = String(localized: "Retry the action in the app to use this one-time permission.")
            }
            return
        }
        BrowserActionPermissions(preferences: preferences).allow(kind: item.kind, account: item.scope.accountPubkey,
                                                                origin: item.scope.origin, duration: duration, destination: item.destination)
        let retryIDs = blockedRequests.filter { $0.kind == item.kind && $0.scope == item.scope && $0.destination == item.destination && $0.waiting }.map(\.id)
        blockedRequests.removeAll { $0.kind == item.kind && $0.scope == item.scope && $0.destination == item.destination }
        grantFeedback = retryIDs.isEmpty ? String(localized: "Permission saved. Retry the action in the app.") : String(localized: "Permission saved. This action is now allowed.")
        for id in retryIDs {
            armTimeout(id, seconds: 15)
            authorizeAndSign(id, relaySettings: [])
        }
    }

    func declineBlockedRequest(_ id: UUID) {
        if blockedRequests.contains(where: { $0.id == id && $0.kind == -1 }) {
            endConnectionRequest(id, reason: "Nostur declined this request.")
        }
        if let request = takePending(id) { request.reply(nil, "Nostur declined this request.") }
        blockedRequests.removeAll { $0.id == id }
    }

    func revokeAction(_ kind: Int, destination: String? = nil) {
        guard let origin else { return }
        BrowserActionPermissions(preferences: preferences).revoke(kind: kind, account: accountPubkey, origin: origin, destination: destination)
        cancelPending()
        objectWillChange.send()
    }

    private func armTimeout(_ id: UUID, seconds: UInt64) {
        timeouts.removeValue(forKey: id)?.cancel()
        timeouts[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self else { return }
            if self.blockedRequests.contains(where: { $0.id == id && $0.kind == -1 }) {
                self.endConnectionRequest(id, reason: "Request expired. Retry the action after allowing it.")
            } else if self.blockedRequests.contains(where: { $0.id == id }) {
                self.takePending(id)?.reply(nil, "Request expired. Retry the action after allowing it.")
            } else { self.reject(id, reason: String(localized: "Signing request expired.")) }
        }
    }

    private func takePending(_ id: UUID) -> PendingRequest? {
        oneTimeApprovals.remove(id)
        timeouts.removeValue(forKey: id)?.cancel()
        signer.cancel(id)
        if let index = blockedRequests.firstIndex(where: { $0.id == id }) { blockedRequests[index].waiting = false }
        return pending.removeValue(forKey: id)
    }

    private func cancelPending() {
        if let item = blockedRequests.first(where: { $0.kind == -1 }) {
            endConnectionRequest(item.id, reason: "Browser session changed.")
        }
        oneTimeRetries.removeAll()
        blockedRequests.removeAll()
        grantFeedback = nil
        for id in Array(pending.keys) {
            takePending(id)?.reply(nil, "Browser session changed.")
        }
    }

    private func record(_ detail: String, blocked: Bool, showNotice: Bool = true, id: UUID = UUID()) {
        activity.removeAll { $0.id == id }
        activity.insert(BrowserActivity(id: id, site: origin ?? "", detail: detail, blocked: blocked), at: 0)
        activity = Array(activity.prefix(30))
        if blocked && showNotice { notice = detail }
    }

    private func currentScope() -> BrowserRequestScope? {
        connected ? documentScope() : nil
    }

    private func documentScope() -> BrowserRequestScope? {
        guard isPresented, webView.window != nil, !isHome, documentReady,
              let documentToken, let origin, BrowserSigningPolicy.origin(webView.url) == origin,
              UIApplication.shared.applicationState == .active,
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
              let scope = documentScope(), frameOrigin == scope.origin,
              request.documentToken == scope.documentToken else {
            reply(nil, "Nostur signing is unavailable for this page."); return
        }
        guard connected else {
            guard request.event?.kind != 22242, pendingConnection.count < 4 else {
                reply(nil, "Nostur signing is unavailable for this page.")
                return
            }
            let item = blockedRequests.first { $0.kind == -1 && $0.scope == scope }
            let id = item?.id ?? UUID()
            pendingConnection.append(PendingConnection(request: request, reply: reply))
            if let index = blockedRequests.firstIndex(where: { $0.id == id }) {
                if !blockedRequests[index].waiting {
                    blockedRequests[index].waiting = true
                    armTimeout(id, seconds: approvalWaitSeconds)
                }
            } else {
                let reason = String(localized: "This site wants to use your Nostur account.")
                blockedRequests.insert(BrowserBlockedRequest(id: id, scope: scope, kind: -1,
                    reason: reason, canAllow: true, waiting: true), at: 0)
                record(reason, blocked: true, showNotice: false, id: id)
                armTimeout(id, seconds: approvalWaitSeconds)
            }
            return
        }
        receiveConnected(request, scope: scope, reply: reply)
    }

    private func allowConnection(_ item: BrowserBlockedRequest, duration: BrowserGrantDuration) {
        guard let connectionKey = preferenceKey("connected"), let appActionsKey = preferenceKey("social") else { return }
        let requests = pendingConnection
        pendingConnection.removeAll()
        timeouts.removeValue(forKey: item.id)?.cancel()
        if duration == .always {
            preferences.set(true, forKey: connectionKey)
            if preferences.object(forKey: appActionsKey) == nil { preferences.set(true, forKey: appActionsKey) }
        } else {
            temporaryConnection = item.scope
        }
        blockedRequests.removeAll { $0.id == item.id }
        activity.removeAll { $0.id == item.id }
        grantFeedback = requests.isEmpty ? String(localized: "Account connected. Retry signing in on the site.") : String(localized: "Account connected.")
        for request in requests {
            receiveConnected(request.request, scope: item.scope, reply: request.reply)
        }
    }

    private func endConnectionRequest(_ id: UUID, reason: String) {
        timeouts.removeValue(forKey: id)?.cancel()
        let requests = pendingConnection
        pendingConnection.removeAll()
        if let index = blockedRequests.firstIndex(where: { $0.id == id }) { blockedRequests[index].waiting = false }
        for request in requests { request.reply(nil, reason) }
    }

    private func receiveConnected(_ request: BrowserBridgeRequest, scope: BrowserRequestScope, reply: @escaping (Any?, String?) -> Void) {
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
        record(reason, blocked: true, showNotice: false, id: id)
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
                                                       websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed, relaySettings: relaySettings, accountChanges: accountChangesAllowed, deletions: deletionsAllowed, wallet: walletAllowed, allowedKinds: allowedKinds, httpDestinations: httpDestinations) {
            let destination = BrowserSigningPolicy.externalHTTPDestination(for: event, from: request.scope.origin)
            guard BrowserSigningPolicy.canGrant(event.kind),
                  signingApproval(for: request, relaySettings: relaySettings, allowOnce: true) != nil else {
                reject(id, reason: reason)
                return
            }
            if let retry = oneTimeRetries.firstIndex(where: {
                $0.scope == request.scope && $0.kind == event.kind && $0.destination == destination
                    && $0.event?.tags == event.tags && $0.event?.content == event.content
            }) {
                oneTimeRetries.remove(at: retry)
                oneTimeApprovals.insert(id)
            }
            if !oneTimeApprovals.contains(id) {
                if !blockedRequests.contains(where: { $0.id == id }) {
                    blockedRequests.insert(BrowserBlockedRequest(id: id, scope: request.scope, kind: event.kind,
                        reason: reason, canAllow: true, waiting: true, destination: destination, event: event), at: 0)
                    record(reason, blocked: true, showNotice: false, id: id)
                    armTimeout(id, seconds: approvalWaitSeconds)
                }
                return
            }
        }
        let now = Date()
        signatureTimes.removeAll { now.timeIntervalSince($0) >= 60 }
        guard signatureTimes.count < 20 else {
            reject(id, reason: String(localized: "Signing limit reached. Try again in a minute.")); return
        }
        guard let approval = signingApproval(for: request, relaySettings: relaySettings, allowOnce: oneTimeApprovals.contains(id)) else {
            reject(id, reason: String(localized: "This request is not authorized.")); return
        }
        signatureTimes.append(now)
        signer.sign(approval, requestID: id) { [weak self] result in self?.finish(id, result: result) }
    }

    private func signingApproval(for request: PendingRequest, relaySettings: [BrowserRelaySetting],
                                 allowOnce: Bool) -> BrowserSigningApproval? {
        var kinds = allowedKinds
        var destinations = httpDestinations
        if allowOnce {
            if let destination = BrowserSigningPolicy.externalHTTPDestination(for: request.event, from: request.scope.origin) {
                destinations.insert(destination)
            } else {
                kinds.insert(request.event.kind)
            }
        }
        return BrowserSigningPolicy.approval(for: request.event, accountPubkey: request.scope.accountPubkey,
                                             origin: request.scope.origin, connected: connected, social: socialAllowed,
                                             websiteAuth: websiteAuthAllowed, uploads: uploadsAllowed,
                                             relaySettings: relaySettings, accountChanges: accountChangesAllowed,
                                             deletions: deletionsAllowed, wallet: walletAllowed,
                                             allowedKinds: kinds, httpDestinations: destinations)
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
              signingApproval(for: request, relaySettings: relaySettings, allowOnce: oneTimeApprovals.contains(id)) != nil else {
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
            record(String(localized: "Signed: \(name) (kind \(kind))."), blocked: false, id: id)
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
        if trustedVisit?.origin != BrowserSigningPolicy.origin(webView.url) { trustedVisit = nil }
        if temporaryConnection?.origin != BrowserSigningPolicy.origin(webView.url) { temporaryConnection = nil }
        documentReady = true
        let token = UUID().uuidString
        documentToken = token
        currentURL = webView.url
        address = webView.url?.absoluteString ?? ""
        addressEdited = false
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
        if webView === self.webView, isPresented, navigationAction.sourceFrame.isMainFrame, let url = navigationAction.request.url,
           let targetOrigin = BrowserSigningPolicy.origin(url) {
            if trustedVisit?.origin != targetOrigin { trustedVisit = nil }
            if temporaryConnection?.origin != targetOrigin { temporaryConnection = nil }
            load(url)
        }
        return nil
    }
}

