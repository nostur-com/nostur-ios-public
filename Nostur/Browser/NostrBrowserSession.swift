import SwiftUI

/// Owns the WebKit session beyond the lifetime of its full-screen presentation.
/// The model is created only when the browser is first opened.
@MainActor
final class NostrBrowserSession: ObservableObject {
    static let shared = NostrBrowserSession()

    @Published private(set) var browser: NostrBrowserModel?
    @Published private(set) var isPresented = false
    @Published private(set) var minimizedHost: String?

    var isMinimized: Bool { browser != nil && !isPresented }

    func present() {
        if browser == nil { browser = NostrBrowserModel() }
        browser?.setPresented(true)
        isPresented = true
    }

    func open(_ url: URL, from post: BrowserPostSource? = nil) {
        guard BrowserSigningPolicy.origin(url) != nil else { return }
        present()
        if browser?.accountPubkey.isEmpty == true, let account = AccountsState.shared.loggedInAccount?.account {
            browser?.selectAccount(account)
        }
        browser?.openPostLink(url, source: post)
    }

    func minimize() {
        browser?.setPresented(false)
        minimizedHost = browser?.currentURL?.host
        isPresented = false
    }

    func close() {
        browser?.close()
        isPresented = false
        browser = nil
        minimizedHost = nil
    }
}

struct NostrBrowserPresentation: ViewModifier {
    @Environment(\.theme) private var theme
    @ObservedObject var session = NostrBrowserSession.shared
    let account: LoggedInAccount

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if session.isMinimized {
                    BrowserReturnButton(session: session)
                        .padding(.trailing, 12)
                        .padding(.bottom, 64)
                }
            }
            .fullScreenCover(isPresented: Binding(get: { session.isPresented }, set: { presented in
                if presented { session.present() } else { session.minimize() }
            })) {
                if let browser = session.browser {
                    NostrBrowserView(browser: browser, minimize: session.minimize, close: session.close)
                        .environment(\.theme, theme)
                        .environmentObject(account)
                        .interactiveDismissDisabled()
                        .presentationBackgroundCompat(theme.listBackground)
                }
            }
    }
}

private struct BrowserReturnButton: View {
    @ObservedObject var session: NostrBrowserSession

    var body: some View {
        Button { session.present() } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Return to web app").font(.caption.bold())
                    if let host = session.minimizedHost {
                        Text(host).font(.caption2).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: 240)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(Capsule())
        .shadow(radius: 3, y: 2)
        .accessibilityLabel("Return to web app")
        .accessibilityHint("Resume the page you minimized")
    }
}
