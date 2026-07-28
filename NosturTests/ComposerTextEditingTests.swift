import Testing
import UIKit
import SwiftUI
import NostrEssentials
@testable import Nostur

@MainActor
struct ComposerTextEditingTests {
    @Test func mentionAutocompleteReplacesInMiddleWithoutMovingToEnd() throws {
        let textView = UITextView()
        textView.text = "Before 😀 @fa after"
        let source = textView.text as NSString
        let tokenRange = source.range(of: "@fa")
        textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)

        let replacementRange = try #require(autocompleteReplacementRange(
            trigger: "@",
            term: "fa",
            textView: textView
        ))
        let pubkey = String(repeating: "01", count: 32)
        let replacement = composerMention(name: "Fabian", pubkey: pubkey)
        let insertionPoint = try #require(
            textView.replaceTextStorageCharacters(in: replacementRange, with: replacement)
        )

        #expect(textView.text == "Before 😀 @Fabian  after")
        #expect(textView.selectedRange == insertionPoint)
        #expect(insertionPoint.location < textView.textStorage.length)
        let mentionLocation = (textView.text as NSString).range(of: "@Fabian").location
        #expect(textView.textStorage.attribute(
            .nosturMentionPubkey,
            at: mentionLocation,
            effectiveRange: nil
        ) as? String == pubkey)
    }

    @Test func customEmojiAutocompleteUsesUTF16Offsets() throws {
        let textView = UITextView()
        textView.text = "👨‍👩‍👧‍👦 hello :par world"
        let source = textView.text as NSString
        let tokenRange = source.range(of: ":par")
        textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)

        let replacementRange = try #require(autocompleteReplacementRange(
            trigger: ":",
            term: "par",
            textView: textView
        ))
        let insertionPoint = try #require(
            textView.replaceTextStorageCharacters(
                in: replacementRange,
                with: ":party_parrot: "
            )
        )

        #expect(textView.text == "👨‍👩‍👧‍👦 hello :party_parrot:  world")
        #expect(textView.selectedRange == insertionPoint)
        #expect(insertionPoint.location < textView.textStorage.length)
    }

    @Test func autocompleteRejectsAStaleSearchTerm() {
        let textView = UITextView()
        textView.text = "Hello @fab"
        textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)

        #expect(autocompleteReplacementRange(
            trigger: "@",
            term: "different",
            textView: textView
        ) == nil)
    }

    @Test func termDetectionHandlesEmojiBeforeCursor() {
        let textView = UITextView()
        textView.text = "👨‍👩‍👧‍👦 hello @fab later"
        let source = textView.text as NSString
        let tokenRange = source.range(of: "@fab")
        textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)

        #expect(mentionTerm(textView.text, textView: textView) == "fab")
    }

    @Test func completedMentionDoesNotRestartAutocomplete() {
        let textView = UITextView()
        let completedMention = composerMention(
            name: "Fabian",
            pubkey: String(repeating: "01", count: 32)
        )
        let text = NSMutableAttributedString(string: "Hello ")
        text.append(completedMention)
        textView.attributedText = text
        textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)

        #expect(mentionTerm(textView.text, textView: textView) == nil)
    }

    @Test func mentionQueryAllowsSpacesInDisplayNames() {
        let text = "Testing @Space "

        #expect(mentionQueryTerm(
            in: text,
            cursorUTF16Location: (text as NSString).length
        ) == "Space ")
    }

    @Test func mentionQueryDoesNotStartInsideAnEmailAddress() {
        let text = "test@example.com"

        #expect(mentionQueryTerm(
            in: text,
            cursorUTF16Location: (text as NSString).length
        ) == nil)
    }

    @Test func semanticMentionPublishesUsingItsPubkey() throws {
        let pubkey = String(repeating: "01", count: 32)
        let mention = composerMention(name: "Different Display Name", pubkey: pubkey)
        let expectedNpub = try NIP19(prefix: "npub", hexString: pubkey).displayString

        #expect(replaceSemanticMentionsWithNpubs(mention) == "nostr:\(expectedNpub) ")
    }

    @Test func liveChatImmediateSubmitConsumesPendingMention() throws {
        let pubkey = String(repeating: "01", count: 32)
        let semanticMessage = try #require(completingChatMention(
            message: "Testing @tes",
            attributedMessage: NSAttributedString(string: "Testing @tes"),
            term: "tes",
            name: "Tester",
            pubkey: pubkey
        ))
        let expectedNpub = try NIP19(prefix: "npub", hexString: pubkey).displayString

        #expect(semanticMessage.string == "Testing @Tester ")
        #expect(semanticMessage.nosturMentionRuns().first?.pubkey == pubkey)
        #expect(replaceSemanticMentionsWithNpubs(semanticMessage) == "Testing nostr:\(expectedNpub) ")
    }

    @Test func liveChatDoesNotApplyAStalePendingMention() {
        let semanticMessage = completingChatMention(
            message: "Testing @someone-else",
            attributedMessage: NSAttributedString(string: "Testing @someone-else"),
            term: "tes",
            name: "Tester",
            pubkey: String(repeating: "01", count: 32)
        )

        #expect(semanticMessage == nil)
    }

    @Test func liveChatCompletesANameContainingSpaces() throws {
        let pubkey = String(repeating: "01", count: 32)
        let semanticMessage = try #require(completingChatMention(
            message: "Testing @Space ",
            attributedMessage: NSAttributedString(string: "Testing @Space "),
            term: "Space ",
            name: "Space Testur",
            pubkey: pubkey
        ))

        #expect(semanticMessage.string == "Testing @Space Testur ")
        #expect(semanticMessage.nosturMentionRuns().first?.pubkey == pubkey)
    }

    @Test func liveChatCursorMovesPastExpandedMention() {
        let newText = "Testing @Tester "

        for oldText in ["Testing @tes", "Testing @Tes"] {
            let oldSelection = NSRange(
                location: (oldText as NSString).length,
                length: 0
            )
            let newSelection = selectionAfterExternalTextChange(
                from: oldText,
                to: newText,
                selectedRange: oldSelection
            )

            #expect(newSelection == NSRange(
                location: (newText as NSString).length,
                length: 0
            ))
        }
    }

    @Test func unmatchedMentionStaysPlainText() {
        let source = "@not-a-match #topic"
        let editor = makeEditor(text: source, highlightRules: NewPostModel.rules)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        textView.text = source

        coordinator.applyHighlighting(to: textView)

        let mentionRange = (source as NSString).range(of: "@not-a-match")
        let hashtagRange = (source as NSString).range(of: "#topic")
        #expect(textView.textStorage.attribute(
            .nosturMentionPubkey,
            at: mentionRange.location,
            effectiveRange: nil
        ) == nil)
        #expect(textView.textStorage.attribute(
            .foregroundColor,
            at: mentionRange.location,
            effectiveRange: nil
        ) as? UIColor != UIColor(Themes.default.theme.accent))
        #expect(textView.textStorage.attribute(
            .foregroundColor,
            at: hashtagRange.location,
            effectiveRange: nil
        ) as? UIColor == UIColor(Themes.default.theme.accent))
        #expect(replaceSemanticMentionsWithNpubs(textView.attributedText) == source)
    }

    @Test func autocompleteReplacementIsOneUndoableAction() throws {
        let textView = UndoableTextView()
        textView.text = "Before @fa after"
        let tokenRange = (textView.text as NSString).range(of: "@fa")
        textView.selectedRange = NSRange(location: NSMaxRange(tokenRange), length: 0)
        let pubkey = String(repeating: "01", count: 32)

        _ = textView.replaceTextStorageCharacters(
            in: tokenRange,
            with: composerMention(name: "Fabian", pubkey: pubkey),
            undoActionName: "Mention"
        )

        #expect(textView.text == "Before @Fabian  after")
        textView.testUndoManager.undo()
        #expect(textView.text == "Before @fa after")
        #expect(textView.selectedRange == NSRange(location: NSMaxRange(tokenRange), length: 0))
        textView.testUndoManager.redo()
        #expect(textView.text == "Before @Fabian  after")
        #expect(textView.attributedText.nosturMentionRuns().first?.pubkey == pubkey)
    }

    @Test func draftUndoRoundTripKeepsSemanticMentionIdentity() {
        let drafts = Drafts.shared
        let originalDraft = drafts.draft
        let originalDraftMentions = drafts.draftMentions
        let originalRestoreDraft = drafts.restoreDraft
        let originalRestoreMentions = drafts.restoreDraftMentions
        defer {
            drafts.draft = originalDraft
            drafts.draftMentions = originalDraftMentions
            drafts.restoreDraft = originalRestoreDraft
            drafts.restoreDraftMentions = originalRestoreMentions
        }

        let record = ComposerMentionRecord(
            location: 0,
            length: 7,
            pubkey: String(repeating: "01", count: 32),
            text: "@Fabian"
        )
        drafts.draft = "@Fabian hello"
        drafts.draftMentions = [record]

        drafts.preserveDraftForUndoSend()
        drafts.clearActiveDraftAfterSchedulingSend()
        #expect(drafts.draft.isEmpty)
        #expect(drafts.draftMentions.isEmpty)
        #expect(drafts.restoreDraft == "@Fabian hello")
        #expect(drafts.restoreDraftMentions == [record])

        drafts.restoreDraftAfterUndoSend()

        #expect(drafts.draft == "@Fabian hello")
        #expect(drafts.draftMentions == [record])
        #expect(drafts.restoreDraft.isEmpty)
        #expect(drafts.restoreDraftMentions.isEmpty)
    }

    @Test func openingAnotherComposerDoesNotClearUndoSendDraft() async {
        let drafts = Drafts.shared
        let originalDraft = drafts.draft
        let originalDraftMentions = drafts.draftMentions
        let originalRestoreDraft = drafts.restoreDraft
        let originalRestoreMentions = drafts.restoreDraftMentions
        defer {
            drafts.draft = originalDraft
            drafts.draftMentions = originalDraftMentions
            drafts.restoreDraft = originalRestoreDraft
            drafts.restoreDraftMentions = originalRestoreMentions
        }

        drafts.draft = ""
        drafts.restoreDraft = "Currently awaiting send"
        _ = TypingTextModel()
        await Task.yield()

        #expect(drafts.draft.isEmpty)
        #expect(drafts.restoreDraft == "Currently awaiting send")
    }

    @Test func editingSemanticMentionInvalidatesItsPubkey() {
        let pubkey = String(repeating: "01", count: 32)
        let editor = makeEditor(text: "@Fabian ")
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        textView.attributedText = composerMention(name: "Fabian", pubkey: pubkey)

        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementText: "x"
        )

        #expect(textView.attributedText.nosturMentionRuns().isEmpty)
    }

    @Test func highlightingChangesAttributesWithoutChangingTextOrSelection() throws {
        let source = "Before @fab after"
        let rule = HighlightRule(
            pattern: try NSRegularExpression(pattern: "@\\w+"),
            formattingRule: TextFormattingRule(key: .foregroundColor, value: UIColor.systemBlue)
        )
        let editor = makeEditor(text: source, highlightRules: [rule])
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        textView.text = source
        textView.selectedRange = NSRange(location: 4, length: 0)

        coordinator.applyHighlighting(to: textView)

        #expect(textView.text == source)
        #expect(textView.selectedRange == NSRange(location: 4, length: 0))
        let mentionRange = (source as NSString).range(of: "@fab")
        #expect(textView.textStorage.attribute(
            .foregroundColor,
            at: mentionRange.location,
            effectiveRange: nil
        ) as? UIColor == UIColor.systemBlue)
    }

    @Test func highlightingPreservesSemanticMentionIdentity() {
        let pubkey = String(repeating: "01", count: 32)
        let mention = composerMention(name: "Fabian Example", pubkey: pubkey)
        let editor = makeEditor(text: mention.string)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        textView.attributedText = mention
        textView.selectedRange = NSRange(location: mention.length, length: 0)

        coordinator.applyHighlighting(to: textView)

        let run = textView.attributedText.nosturMentionRuns().first
        #expect(run?.pubkey == pubkey)
        #expect(run?.text == "@Fabian Example")
        #expect(textView.selectedRange == NSRange(location: mention.length, length: 0))
    }

    @Test func incrementalHighlightingDoesNotRestyleOtherParagraphs() {
        let source = "first paragraph\nsecond #topic"
        let editor = makeEditor(text: source, highlightRules: NewPostModel.rules)
        let coordinator = editor.makeCoordinator()
        let textView = UITextView()
        textView.text = source
        coordinator.applyHighlighting(to: textView)

        let firstRange = (source as NSString).range(of: "first")
        let sentinel = NSAttributedString.Key("test.sentinel")
        textView.textStorage.addAttribute(sentinel, value: true, range: firstRange)
        let editedRange = (source as NSString).range(of: "#topic")

        coordinator.applyHighlighting(to: textView, editedRange: editedRange)

        #expect(textView.textStorage.attribute(
            sentinel,
            at: firstRange.location,
            effectiveRange: nil
        ) as? Bool == true)
    }

    private func makeEditor(
        text: String,
        highlightRules: [HighlightRule] = []
    ) -> HighlightedTextEditor {
        HighlightedTextEditor(
            text: .constant(text),
            showVoiceRecorderButton: .constant(false),
            pastedImages: .constant([]),
            pastedVideos: .constant([]),
            shouldBecomeFirstResponder: false,
            highlightRules: highlightRules
        )
    }
}

@MainActor
private final class UndoableTextView: UITextView {
    let testUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        testUndoManager
    }
}
