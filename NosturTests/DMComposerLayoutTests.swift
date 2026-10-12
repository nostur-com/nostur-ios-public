import SwiftUI
import Testing
import UIKit
@testable import Nostur

@MainActor
struct DMComposerLayoutTests {
    @Test func typingLongMessagesKeepsEditorWithinAvailableWidth() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for width: CGFloat in [320, 440, 768] {
            let host = UIHostingController(rootView: EditorLayoutProbe())
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(nanoseconds: 50_000_000)
            host.view.layoutIfNeeded()
            let editor = try #require(findEditor(in: host.view))
            let initialWidth = editor.bounds.width
            #expect(initialWidth > 0)

            // Exercise typing into the UIKit view and its SwiftUI binding, rather
            // than just measuring a standalone text view at a manually fixed size.
            for text in [String(repeating: "This is a longer DM sentence. ", count: 12), String(repeating: "a", count: 500)] {
                editor.insertText(text)
                try await Task.sleep(nanoseconds: 50_000_000)
                host.view.layoutIfNeeded()
                #expect(abs(editor.bounds.width - initialWidth) < 1)
                let frame = editor.convert(editor.bounds, to: host.view)
                #expect(frame.minX >= 0)
                #expect(frame.maxX <= width + 1)
                #expect(host.sizeThatFits(in: CGSize(width: width, height: 600)).width <= width + 1)
                #expect(editor.sizeThatFits(CGSize(width: initialWidth, height: .greatestFiniteMagnitude)).height > 120)
                #expect(editor.bounds.height <= 120)
                #expect(editor.isScrollEnabled)
            }
        }
    }

    private func findEditor(in view: UIView) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }
}

private struct EditorLayoutProbe: View {
    @State private var text = "Hi"
    @State private var height: CGFloat = 36

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .frame(width: 28, height: 28)
            MentionHighlightingTextView(
                text: $text,
                attributedText: nil,
                height: $height,
                accentColor: .systemBlue,
                onSubmit: nil
            )
            .frame(maxWidth: .infinity)
            .frame(height: min(height, 120))
            .padding(10)
            .padding(.trailing, 40)
        }
        .padding(.horizontal, 10)
    }
}
