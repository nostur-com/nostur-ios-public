import SwiftUI
import UIKit

/// Link previews own their hold/tap recognizer instead of depending on a
/// context-menu recognizer embedded in a swipeable List row.
struct BrowserPostLinkMenu: ViewModifier {
    @Environment(\.theme) private var theme
    let url: URL
    @State private var showActions = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first(true): showActions = true
                        case .second: UIApplication.shared.open(url)
                        default: break
                        }
                    }
            )
            .accessibilityAddTraits(.isLink)
            .accessibilityAction { UIApplication.shared.open(url) }
            .confirmationDialog("Open Link", isPresented: $showActions, titleVisibility: .visible) {
                actions
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(theme.accent, theme.background)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Link actions")
            }
    }

    @ViewBuilder
    private var actions: some View {
        if BrowserSigningPolicy.origin(url) != nil {
            Button {
                NostrBrowserSession.shared.open(url)
            } label: {
                Label("Open in Nostur Browser", systemImage: "globe")
            }
        }
        Button {
            UIApplication.shared.open(url)
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }
        Button {
            UIPasteboard.general.url = url
        } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
    }
}

@MainActor
final class BrowserPostLinkActions: NSObject, UITextViewDelegate {
    static let shared = BrowserPostLinkActions()

    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard case let .link(url) = textItem.content, BrowserSigningPolicy.origin(url) != nil else { return nil }
        let open = UIAction(title: String(localized: "Open in Nostur Browser"), image: UIImage(systemName: "globe")) { _ in
            NostrBrowserSession.shared.open(url)
        }
        return UITextItem.MenuConfiguration(menu: UIMenu(children: [open] + defaultMenu.children))
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard #unavailable(iOS 17.0), interaction == .presentActions,
              BrowserSigningPolicy.origin(url) != nil,
              var presenter = textView.window?.rootViewController else { return true }
        while let presented = presenter.presentedViewController { presenter = presented }
        let menu = UIAlertController(title: url.absoluteString, message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: String(localized: "Open in Nostur Browser"), style: .default) { _ in
            NostrBrowserSession.shared.open(url)
        })
        menu.addAction(UIAlertAction(title: String(localized: "Open in Browser"), style: .default) { _ in UIApplication.shared.open(url) })
        menu.addAction(UIAlertAction(title: String(localized: "Copy Link"), style: .default) { _ in UIPasteboard.general.url = url })
        menu.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        menu.popoverPresentationController?.sourceView = textView
        menu.popoverPresentationController?.sourceRect = textView.bounds
        presenter.present(menu, animated: true)
        return false
    }
}

/// Feed text keeps its fast SwiftUI renderer. When a post has several links,
/// show the destination for each choice rather than guessing which was held.
struct BrowserPostTextLinkMenu: ViewModifier {
    let text: AttributedString

    private var urls: [URL] {
        var seen = Set<URL>()
        return text.runs.compactMap { run in
            guard let url = run.link, BrowserSigningPolicy.origin(url) != nil,
                  seen.insert(url).inserted else { return nil }
            return url
        }
    }

    func body(content: Content) -> some View {
        let links = urls
        if links.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(links, id: \.absoluteString) { url in
                    Button {
                        NostrBrowserSession.shared.open(url)
                    } label: {
                        if links.count == 1 {
                            Label("Open in Nostur Browser", systemImage: "globe")
                        } else {
                            Label("Open in Nostur Browser: \(url.absoluteString)", systemImage: "globe")
                        }
                    }
                }
            }
        }
    }
}
