import SwiftUI
import XCTest
@testable import Nostur

@MainActor
final class SelectablePostTextLayoutTests: XCTestCase {
    func testShortRepliesWrapAndResizeWithoutLosingLastLine() async throws {
        for sentence in [
            "Blitz Wallet use spark to be non-custodial",
            "Doesn’t spark leak all your transactions?"
        ] {
            let text = NSAttributedString(string: sentence, attributes: [.font: UIFont.systemFont(ofSize: 20)])
            try await assertCompleteLayout(text, widths: [460, 230, 310, 460])
        }
    }

    func testLargeSelectableTextWithLinkAndAttachmentFits() async throws {
        let text = NSMutableAttributedString(
            string: "A reply with a link and a custom emoji: ",
            attributes: [.font: UIFont.systemFont(ofSize: 30)]
        )
        text.addAttribute(.link, value: URL(string: "https://nostur.com")!, range: NSRange(location: 15, length: 4))
        let attachment = NSTextAttachment()
        attachment.bounds = CGRect(x: 0, y: -4, width: 30, height: 30)
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: "\nThe final line must remain visible.", attributes: [.font: UIFont.systemFont(ofSize: 30)]))
        try await assertCompleteLayout(text, widths: [350, 220, 350])
    }

    private func assertCompleteLayout(_ text: NSAttributedString, widths: [CGFloat]) async throws {
        let parsed = AttributedStringWithPs(input: text.string, output: text, pTags: [])
        // Deliberately supply a wider environment value than the actual layout.
        // Nesting or resizing must use the proposed width, not this estimate.
        let host = UIHostingController(rootView: ScrollView {
            LazyVStack(alignment: .leading) {
                NRContentTextRenderer(
                    attributedStringWithPs: parsed, showMore: .constant(true),
                    availableWidth: 600, isDetail: true, theme: Themes.default.theme,
                    nxViewingContext: [.selectableText]
                )
            }
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: widths[0], height: 1000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var previousTextView: UITextView?
        for width in widths {
            window.frame.size.width = width
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            host.view.layoutIfNeeded()
            let view = try XCTUnwrap(findTextView(in: host.view))
            if let previousTextView {
                XCTAssertTrue(view === previousTextView, "Resize must remeasure the existing text view")
            }
            previousTextView = view
            XCTAssertEqual(view.attributedText.string, text.string)
            XCTAssertEqual(view.bounds.width, width, accuracy: 1)
            let needed = view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude))
            XCTAssertGreaterThanOrEqual(view.bounds.height + 0.5, needed.height, "Clipped at width \(width)")
            view.layoutManager.ensureLayout(for: view.textContainer)
            let glyphs = view.layoutManager.glyphRange(for: view.textContainer)
            let used = view.layoutManager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
            XCTAssertGreaterThanOrEqual(view.bounds.height + 0.5, used.maxY)
        }
    }

    private func findTextView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }
}
