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
    @ObservedObject var browser: NostrBrowserModel
    var body: some View {
        Button {
            if browser.blockedRequests.isEmpty { browser.settingsShown = true }
            else { browser.blockedRequestsShown = true }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: browser.blockedRequests.isEmpty ? "slider.horizontal.3" : "exclamationmark.shield")
                if !browser.blockedRequests.isEmpty {
                    Text(browser.blockedRequests.count.formatted())
                        .font(.caption2.bold())
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 44, minHeight: 44)
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
                BrowserBlockedRequestsContent(browser: browser)
            }
            .navigationTitle("Blocked requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss blocked requests")
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

private struct BrowserBlockedRequestsContent: View {
    @ObservedObject var browser: NostrBrowserModel
    var showEmptyState = true

    var body: some View {
        if showEmptyState || !browser.blockedRequests.isEmpty {
            Section {
                if let feedback = browser.grantFeedback {
                    Text(feedback).font(.callout)
                }
                if browser.blockedRequests.isEmpty { Text("No blocked requests.").foregroundStyle(.secondary) }
                ForEach(browser.blockedRequests) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.actionName).font(.headline)
                            Spacer()
                            Button { browser.declineBlockedRequest(item.id) } label: {
                                Image(systemName: "xmark").frame(minWidth: 32, minHeight: 32)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Dismiss request")
                        }
                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        if [0, 3, 5, 10002, 10050].contains(item.kind) {
                            Text("This can change shared account data used by your other Nostr apps.")
                                .font(.callout)
                        }
                        if browser.canAllow(item) {
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
                    }
                }
            } header: {
                Text("Requested actions")
            } footer: {
                if browser.blockedRequests.contains(where: { browser.canAllow($0) }) {
                    Text("Allow today ends at midnight. Always allow stays enabled until you remove it.")
                }
            }
        }
        if !browser.actionGrants.isEmpty {
            Section("Extra permissions") {
                ForEach(browser.actionGrants) { grant in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(BrowserEventDescription.name(for: grant.kind))
                            Text(grant.isPermanent ? "Always allowed" : "Allowed today")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { browser.revokeAction(grant.kind) } label: {
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
}

private struct BrowserDirectoryView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var browser: NostrBrowserModel

    var body: some View {
        let favorites = BrowserDirectory.all.filter { browser.favorites.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrowserDirectoryHeader()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], alignment: .leading, spacing: 12) {
                    if !favorites.isEmpty {
                        BrowserDirectoryCategory(section: BrowserDirectorySection(id: "favorites", title: "Favorites", icon: "star", apps: favorites, keywords: ""), browser: browser)
                    }
                    ForEach(BrowserDirectory.sections) { section in
                        BrowserDirectoryCategory(section: section, browser: browser)
                    }
                }
                Text("Choose an app's browser extension login to use your Nostur account. Some features may request signatures this browser does not support yet.")
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
            Form {
                Section {
                    Text(browser.origin ?? "").font(.headline)
                    LabeledContentCompat(title: "Account", value: browser.accountName)
                    Toggle(isOn: Binding(get: { browser.connected }, set: { browser.setConnected($0) })) {
                        BrowserPermissionLabel(title: "Use my Nostur account", detail: "Let this app use your public identity and sign its app data. Your private key stays in Nostur.")
                    }
                } footer: {
                    Text("Turning this off stops signing and clears this website’s saved login.")
                }
                Section {
                    Toggle(isOn: Binding(get: { browser.socialAllowed }, set: { browser.setSocial($0) })) {
                        BrowserPermissionLabel(title: "Post & react", detail: "Publish posts, comments, reactions, polls and articles.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.websiteAuthAllowed }, set: { browser.setWebsiteAuth($0) })) {
                        BrowserPermissionLabel(title: "Sign in to services", detail: BrowserSiteDefaults.isHomepageApp(browser.origin ?? "")
                            ? "Let this app authorize sign-in, uploads and other requests to HTTPS services."
                            : "Let this app authorize sign-in, uploads and other requests to this website.")
                    }
                    .disabled(!browser.connected)
                    Toggle(isOn: Binding(get: { browser.uploadsAllowed }, set: { browser.setUploads($0) })) {
                        BrowserPermissionLabel(title: "Upload media", detail: "Allow Blossom uploads for individual files. Other uploads can also use Sign in to services.")
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
                    Text("Enabled actions run without asking each time.")
                    if !browser.actionGrants.isEmpty {
                        Text("Extra permissions below can allow individual actions. Turning a switch off removes existing allowances for that category.")
                    }
                }
                BrowserBlockedRequestsContent(browser: browser, showEmptyState: false)
                if !browser.activity.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach(browser.activity) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(item.detail, systemImage: item.blocked ? "hand.raised" : "checkmark.shield")
                                    Text(item.site).font(.caption).foregroundStyle(.secondary)
                                    Text(item.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            HStack {
                                Label("Recent activity", systemImage: "clock")
                                Spacer()
                                Text(browser.activity.count.formatted())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
            Text("Other websites and Nostur accounts keep their own choices.")
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

