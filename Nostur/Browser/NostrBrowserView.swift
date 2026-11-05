import SwiftUI
import WebKit
import CoreData
import NavigationBackport

struct NostrBrowserView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    @ObservedObject var browser: NostrBrowserModel
    let minimize: () -> Void
    let close: () -> Void

    var body: some View {
        Group {
            if browser.isHome {
                BrowserDirectoryView(browser: browser)
            } else {
                BrowserWebView(webView: browser.webView)
                    .id(ObjectIdentifier(browser.webView))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.listBackground)
        .tint(theme.accent)
        .modifier(BrowserBottomBar(browser: browser, minimize: minimize, close: close))
        .overlay(alignment: .top) {
            if let notice = browser.notice {
                BrowserNotice(message: notice, browser: browser)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
        .onAppear { if browser.accountPubkey.isEmpty { browser.selectAccount(la.account) } }
        .sheet(isPresented: $browser.blockedRequestsShown, onDismiss: {
            if browser.openSettingsAfterBlockedRequests {
                browser.openSettingsAfterBlockedRequests = false
                if browser.isPresented { browser.settingsShown = true }
            }
        }) {
            BrowserBlockedRequestsView(browser: browser)
        }
        .sheet(isPresented: $browser.settingsShown) {
            BrowserSiteSettings(browser: browser)
        }
    }
}

/// Keep the native bar treatment outside the web view and directory scroll view.
private struct BrowserBottomBar: ViewModifier {
    @ObservedObject var browser: NostrBrowserModel
    let minimize: () -> Void
    let close: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom) {
                GlassEffectContainer {
                    BrowserControls(browser: browser, minimize: minimize, close: close)
                        .frame(maxWidth: 600)
                        .glassEffect(.regular, in: .rect(cornerRadius: browser.isHome || browser.controlsExpanded ? 26 : 28))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                BrowserControls(browser: browser, minimize: minimize, close: close)
                    .frame(maxWidth: 600)
                    .background(.bar)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

private struct BrowserNotice: View {
    let message: String
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                browser.settingsShown = true
                browser.notice = nil
            } label: {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Open website controls to read the full signing activity")
            Button { browser.notice = nil } label: {
                Image(systemName: "xmark").frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task(id: message) {
            do { try await Task.sleep(nanoseconds: 6_000_000_000) } catch { return }
            if browser.notice == message { browser.notice = nil }
        }
    }
}

private struct BrowserControls: View {
    @ObservedObject var browser: NostrBrowserModel
    let minimize: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if browser.isHome || browser.controlsExpanded {
                HStack(spacing: 6) {
                    BrowserAddressBar(browser: browser)
                    Button(action: minimize) {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Minimize browser")
                    .accessibilityHint("Return to Nostur and keep this page open")
                    Button(action: close) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss browser")
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                BrowserNavigationControls(browser: browser)
            } else {
                HStack(spacing: 0) {
                    Button { browser.controlsExpanded = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.up")
                                .font(.caption.weight(.semibold))
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(browser.currentURL?.host ?? String(localized: "Web apps"))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                HStack(spacing: 5) {
                                    BrowserAccountAvatar(picture: browser.connected ? browser.accountPictureURL : nil, size: 16)
                                    Text(browser.connected ? browser.accountName : String(localized: "Not connected"))
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if browser.loading {
                                ProgressView().controlSize(.small)
                                    .frame(width: 16)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Show browser controls")
                    .accessibilityValue("\(browser.currentURL?.host ?? ""), \(browser.connected ? browser.accountName : String(localized: "Not connected"))")
                    if !browser.blockedRequests.isEmpty {
                        BrowserRequestsButton(browser: browser)
                    }
                    Button(action: minimize) {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Minimize browser")
                    .accessibilityHint("Return to Nostur and keep this page open")
                    Button(action: close) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss browser")
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct BrowserAddressBar: View {
    @ObservedObject var browser: NostrBrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: browser.isHome ? "magnifyingglass" : "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Enter a website address", text: $browser.address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit {
                    focused = false
                    browser.openAddress()
                }
                .accessibilityLabel("Website address")
            if browser.loading {
                ProgressView().scaleEffect(0.8)
            } else if !browser.isHome {
                Button { browser.webView.reload() } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 32, minHeight: 32)
                }
                .accessibilityLabel("Reload page")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 40)
        .modifier(BrowserAddressBackground())
        .padding(.vertical, 4)
    }
}

private struct BrowserAddressBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct BrowserNavigationControls: View {
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        HStack(spacing: 0) {
            Button { browser.webView.goBack() } label: {
                Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(browser.isHome || !browser.canGoBack)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            Button { browser.webView.goForward() } label: {
                Image(systemName: "chevron.forward").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(browser.isHome || !browser.canGoForward)
            .accessibilityLabel("Forward")
            Spacer(minLength: 0)
            Button { browser.home() } label: {
                Image(systemName: "house").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Web app directory")
            Spacer(minLength: 0)
            BrowserAccountMenu(browser: browser)
            Spacer(minLength: 0)
            BrowserRequestsButton(browser: browser)
                .disabled(browser.isHome)
            Spacer(minLength: 0)
            Button { browser.controlsExpanded = false } label: {
                Image(systemName: "chevron.down").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(browser.isHome)
            .accessibilityLabel("Hide browser controls")
        }
        .padding(.horizontal, 8)
    }
}

private struct BrowserAccountAvatar: View {
    @Environment(\.theme) private var theme
    let picture: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let picture {
                MiniPFP(pictureUrl: picture, size: size, fallBackColor: theme.secondaryBackground)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct BrowserAccountMenu: View {
    @ObservedObject var browser: NostrBrowserModel
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CloudAccount.createdAt, ascending: false)])
    private var accounts: FetchedResults<CloudAccount>

    var body: some View {
        Menu {
            Text("Using \(browser.accountName)")
            ForEach(accounts.filter { !$0.isDeleted && $0.managedObjectContext != nil }) { account in
                Button { browser.selectAccount(account) } label: {
                    if account.publicKey == browser.accountPubkey {
                        Label(account.anyName, systemImage: "checkmark")
                    } else {
                        Text(account.anyName)
                    }
                }
            }
        } label: {
            BrowserAccountAvatar(picture: browser.accountPictureURL, size: 22)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Browser account")
        .accessibilityValue(browser.accountName)
    }
}

private struct BrowserRequestsButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seenRequests: Set<UUID> = []
    @State private var isPulsing = false
    @ObservedObject var browser: NostrBrowserModel
    var body: some View {
        let requestIDs = Set(browser.blockedRequests.map(\.id))
        Button {
            if browser.blockedRequests.isEmpty { browser.settingsShown = true }
            else { browser.blockedRequestsShown = true }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: requestIDs.isEmpty ? "slider.horizontal.3" : "exclamationmark.shield.fill")
                    .scaleEffect(isPulsing ? 1.18 : 1)
                    .opacity(isPulsing ? 0.72 : 1)
                if !browser.blockedRequests.isEmpty {
                    Text(browser.blockedRequests.count.formatted())
                        .font(.caption2.bold())
                        .monospacedDigit()
                }
            }
            .foregroundColor(requestIDs.isEmpty ? nil : .orange)
            .frame(minWidth: 44, minHeight: 44)
        }
        .task(id: reduceMotion ? Set<UUID>() : requestIDs) {
            isPulsing = false
            let hasNewRequest = !requestIDs.isSubset(of: seenRequests)
            seenRequests = requestIDs
            guard !reduceMotion, hasNewRequest else { return }
            do {
                for _ in 0..<2 {
                    try Task.checkCancellation()
                    withAnimation(.easeInOut(duration: 0.24)) { isPulsing = true }
                    try await Task.sleep(nanoseconds: 240_000_000)
                    withAnimation(.easeInOut(duration: 0.24)) { isPulsing = false }
                    try await Task.sleep(nanoseconds: 240_000_000)
                }
            } catch { }
        }
        .accessibilityLabel(browser.blockedRequests.isEmpty ? Text("Website controls") : Text("Blocked signing requests"))
        .accessibilityValue(browser.blockedRequests.isEmpty ? "" : browser.blockedRequests.count.formatted())
    }
}

private struct BrowserBlockedRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        NBNavigationStack {
            Form {
                Section {
                    Text(browser.origin ?? "")
                    LabeledContentCompat(title: "Account", value: browser.accountName)
                }
                BrowserRecentActivityContent(browser: browser)
            }
            .navigationTitle("Recent activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss recent activity")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        browser.openSettingsAfterBlockedRequests = true
                        dismiss()
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Website controls")
                }
            }
        }
        .nbUseNavigationStack(.never)
    }
}

private struct BrowserRecentActivityContent: View {
    @ObservedObject var browser: NostrBrowserModel
    var showEmptyState = true

    var body: some View {
        let activeIDs = Set(browser.blockedRequests.map(\.id))
        if showEmptyState || !activeIDs.isEmpty || !browser.activity.isEmpty || !browser.actionGrants.isEmpty {
            Section {
                if let feedback = browser.grantFeedback {
                    Text(feedback).font(.callout)
                }
                if browser.blockedRequests.isEmpty && browser.activity.isEmpty {
                    Text("No recent activity.").foregroundStyle(.secondary)
                }
                ForEach(browser.blockedRequests) { item in
                    BrowserActivityRow(item: browser.activity.first { $0.id == item.id }
                        ?? BrowserActivity(id: item.id, site: item.scope.origin, detail: item.reason, blocked: true)) {
                        BrowserBlockedRequestActions(browser: browser, item: item)
                    }
                }
                ForEach(browser.activity.filter { !activeIDs.contains($0.id) }) { item in
                    BrowserActivityRow(item: item) { EmptyView() }
                }
                if !browser.actionGrants.isEmpty {
                    BrowserSavedPermissions(browser: browser)
                }
            } header: {
                Text("Recent activity")
            } footer: {
                if browser.blockedRequests.contains(where: { browser.canAllow($0) }) {
                    Text("Allow today ends at midnight. Always allow stays enabled until you remove it.")
                }
            }
        }
    }
}

private struct BrowserBlockedRequestActions: View {
    @ObservedObject var browser: NostrBrowserModel
    let item: BrowserBlockedRequest

    var body: some View {
        if [0, 3, 5, 10002, 10050].contains(item.kind) {
            Text("This can change shared account data used by your other Nostr apps.")
                .font(.callout)
        }
        if item.kind == -1, !browser.connected,
           item.scope.origin == browser.origin, item.scope.accountPubkey == browser.accountPubkey {
            Text("Lets this site use your public identity, post, react, and upload media.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Connect and allow app actions") { browser.connectAndAllowAppActions() }
                .buttonStyle(.bordered)
        } else if browser.canAllow(item) {
            if !item.waiting {
                Text("This request has expired. Allow the action, then retry it in the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Allow today") { browser.allowBlockedRequest(item.id, duration: .today) }
                Button("Always allow") { browser.allowBlockedRequest(item.id, duration: .always) }
            }
            .buttonStyle(.bordered)
        } else {
            Text("This request can’t be allowed.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Button("Dismiss request") { browser.declineBlockedRequest(item.id) }
            .buttonStyle(.borderless)
    }
}

private struct BrowserActivityRow<Actions: View>: View {
    let item: BrowserActivity
    @ViewBuilder let actions: () -> Actions
    @State private var copied = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.detail)
                    .textSelection(.enabled)
                if !item.site.isEmpty {
                    Text(item.site)
                        .textSelection(.enabled)
                }
                Text(item.date.formatted(date: .abbreviated, time: .standard))
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = [
                        item.detail,
                        item.site,
                        item.date.formatted(date: .abbreviated, time: .standard)
                    ].filter { !$0.isEmpty }.joined(separator: "\n")
                    copied = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 16)
                        Text("Copy details")
                    }
                }
                .buttonStyle(.borderless)
                actions()
            }
            .font(.caption)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.blocked ? "hand.raised" : "checkmark.shield")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(item.blocked ? Text("Blocked") : Text("Signed"))
                Text(item.detail)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(item.date, style: .time)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.caption)
        }
    }
}

private struct BrowserSavedPermissions: View {
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        DisclosureGroup("Saved permissions") {
            ForEach(browser.actionGrants) { grant in
                HStack {
                    VStack(alignment: .leading) {
                        if let destination = grant.destination {
                            Text("External service: \(destination)")
                        } else {
                            Text(BrowserEventDescription.name(for: grant.kind))
                        }
                        Text(grant.isPermanent ? "Always allowed" : "Allowed today")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { browser.revokeAction(grant.kind, destination: grant.destination) } label: {
                        Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove permission")
                }
            }
        }
        .task(id: browser.actionGrants.filter { !$0.isPermanent }.map(\.expiresAt).min()) {
            guard let expiry = browser.actionGrants.filter({ !$0.isPermanent }).map(\.expiresAt).min() else { return }
            do { try await Task.sleep(nanoseconds: UInt64(max(0, expiry.timeIntervalSinceNow) * 1_000_000_000)) }
            catch { return }
            browser.objectWillChange.send()
        }
    }
}

private struct BrowserDirectoryView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        let favorites = BrowserDirectory.all.filter { browser.favorites.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrowserDirectoryHeader()
                BrowserDirectoryColumns(browser: browser, favorites: favorites)
                Text("Choose an app's browser extension login to use your account. Some features may request signatures this browser does not support yet.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
            }
            .padding(14)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.primary)
        .background(theme.listBackground)
    }
}

private struct BrowserDirectoryColumns: View {
    @ObservedObject var browser: NostrBrowserModel
    let favorites: [BrowserDirectoryApp]

    var body: some View {
        if #available(iOS 16.0, *) {
            BrowserDirectoryLayout {
                BrowserDirectoryCategories(browser: browser, favorites: favorites)
            }
        } else {
            VStack(spacing: 12) {
                BrowserDirectoryCategories(browser: browser, favorites: favorites)
            }
        }
    }
}

private struct BrowserDirectoryCategories: View {
    @ObservedObject var browser: NostrBrowserModel
    let favorites: [BrowserDirectoryApp]

    var body: some View {
        if !favorites.isEmpty {
            BrowserDirectoryCategory(section: BrowserDirectorySection(id: "favorites", title: "Favorites", icon: "star", apps: favorites, keywords: ""), browser: browser)
        }
        ForEach(BrowserDirectory.sections) { section in
            BrowserDirectoryCategory(section: section, browser: browser)
        }
    }
}

private struct BrowserDirectoryHeader: View {
    var body: some View {
        Text("Explore Nostr apps, communities and services.")
            .font(.title2.bold())
    }
}

private struct BrowserDirectoryCategory: View {
    @Environment(\.theme) private var theme
    let section: BrowserDirectorySection
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(section.title, systemImage: section.icon)
                .font(.headline)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.accent)
                .background(theme.accent.opacity(0.12))
            ForEach(section.apps) { app in
                HStack(alignment: .center, spacing: 4) {
                    Button { browser.open(app.url) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.subheadline.bold()).underline().foregroundStyle(theme.accent)
                            Text(app.description).font(.caption).foregroundStyle(theme.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { browser.toggleFavorite(app.id) } label: {
                        Image(systemName: browser.favorites.contains(app.id) ? "star.fill" : "star")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(browser.favorites.contains(app.id) ? Text("Remove \(app.name) from favorites") : Text("Add \(app.name) to favorites"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.lineColor))
    }
}

private struct BrowserSiteSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: NostrBrowserModel
    @State private var permissionInfoShown = false

    var body: some View {
        NBNavigationStack {
            NXForm {
                Section {
                    Text(browser.origin ?? "").font(.headline)
                    LabeledContentCompat(title: "Account", value: browser.accountName)
                    Toggle(isOn: Binding(get: { browser.connected }, set: { browser.setConnected($0) })) {
                        BrowserPermissionLabel(title: "Use account", detail: "Connect your Nostr account to this app.")
                    }
                    if !browser.connected, browser.origin != nil, !browser.accountPubkey.isEmpty {
                        Button("Connect and allow app actions") { browser.connectAndAllowAppActions() }
                    }
                } footer: {
                    Text("Turning this off stops signing and clears this website’s saved login.")
                }
                Section {
                    Toggle(isOn: Binding(get: { browser.socialAllowed }, set: { browser.setSocial($0) })) {
                        BrowserPermissionLabel(title: "App actions", detail: "Use games and apps, post, react, and upload media through Blossom.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.websiteAuthAllowed }, set: { browser.setWebsiteAuth($0) })) {
                        BrowserPermissionLabel(title: "Sign in to this website",
                                               detail: "Authorize sign-ins and other web requests to this site. Other services need their own approval.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.accountChangesAllowed }, set: { browser.setAccountChanges($0) })) {
                        BrowserPermissionLabel(title: "Account changes", detail: "Change your profile, follows, relay lists and other account settings.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.deletionsAllowed }, set: { browser.setDeletions($0) })) {
                        BrowserPermissionLabel(title: "Delete content", detail: "Request removal of your published content.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.walletAllowed }, set: { browser.setWallet($0) })) {
                        BrowserPermissionLabel(title: "Wallet actions", detail: "Let this app request payments and other wallet actions.")
                    }
                    .disabled(!browser.connected)
                } header: {
                    HStack(spacing: 8) {
                        Text("What this app can do")
                        Button { permissionInfoShown = true } label: {
                            Image(systemName: "info.circle")
                                .frame(minWidth: 32, minHeight: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About these permissions")
                        .popover(isPresented: $permissionInfoShown) {
                            BrowserPermissionScopeInfo(site: browser.origin ?? "", account: browser.accountName)
                        }
                    }
                } footer: {
                    if !browser.actionGrants.isEmpty {
                        Text("Saved permissions can allow individual actions. Turning a switch off removes existing allowances for that category.")
                    }
                }
                BrowserRecentActivityContent(browser: browser, showEmptyState: false)

            }
            .navigationTitle("Website controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss website controls")
                }
            }
        }
        .nbUseNavigationStack(.never)
    }
}

private struct BrowserPermissionScopeInfo: View {
    let site: String
    let account: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These choices control what this website can request using this account:").font(.headline)
            Text(site).font(.subheadline).textSelection(.enabled)
            Label(account, systemImage: "person.crop.circle")
            Text("Other websites and accounts keep their own choices.")
        }
        .font(.body)
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(20)
        .frame(idealWidth: 300, maxWidth: 340)
        .modifier(BrowserPermissionPopoverAdaptation())
    }
}

private struct BrowserPermissionPopoverAdaptation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
        }
    }
}

private struct BrowserPermissionLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LabeledContentCompat: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

