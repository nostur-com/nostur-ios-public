//
//  Drafts.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import Foundation

struct ComposerMentionRecord: Codable, Equatable {
    let location: Int
    let length: Int
    let pubkey: String
    let text: String

    var range: NSRange {
        NSRange(location: location, length: length)
    }
}

struct ComposerDraft: Codable, Equatable {
    var text: String = ""
    var mentions: [ComposerMentionRecord] = []
    var emojiURLs: [String: URL] = [:]

    var semanticText: NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        for mention in mentions {
            let range = mention.range
            guard range.location >= 0, range.location <= result.length,
                  range.length > 0, range.length <= result.length - range.location,
                  result.attributedSubstring(from: range).string.utf16.elementsEqual(mention.text.utf16) else { continue }
            result.addAttribute(.nosturMentionPubkey, value: mention.pubkey, range: range)
        }
        return result
    }
}

class Drafts {
    
    static let shared = Drafts()
    
    // This is set when opening a relay feed, with a single relay, to make posting to a single relay easier
    // PostComposer will then show a toggle "Lock post to this relay"
    public var lockToThisRelay: RelayData? = nil
    
    private init() {}
    
    var activeDocument: ComposerDraft {
        get { document(for: "simple_draft") }
        set { save(newValue, for: "simple_draft") }
    }

    private var undoDocument: ComposerDraft {
        get { document(for: "undo_send_restore_draft") }
        set { save(newValue, for: "undo_send_restore_draft") }
    }

    var draft: String {
        get { activeDocument.text }
        set {
            guard !activeDocument.text.utf16.elementsEqual(newValue.utf16) else { return }
            activeDocument = ComposerDraft(text: newValue)
        }
    }

    var restoreDraft: String {
        get { undoDocument.text }
        set {
            guard !undoDocument.text.utf16.elementsEqual(newValue.utf16) else { return }
            undoDocument = ComposerDraft(text: newValue)
        }
    }

    var draftMentions: [ComposerMentionRecord] {
        get { activeDocument.mentions }
        set { activeDocument.mentions = newValue }
    }

    var restoreDraftMentions: [ComposerMentionRecord] {
        get { undoDocument.mentions }
        set { undoDocument.mentions = newValue }
    }

    func preserveDraftForUndoSend() {
        undoDocument = activeDocument
    }

    func clearActiveDraftAfterSchedulingSend() {
        activeDocument = ComposerDraft()
    }

    func restoreDraftAfterUndoSend() {
        activeDocument = undoDocument
        undoDocument = ComposerDraft()
    }

    private func document(for key: String) -> ComposerDraft {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key + "_document"),
           let document = try? JSONDecoder().decode(ComposerDraft.self, from: data) {
            return document
        }
        let mentions = defaults.data(forKey: key + "_mentions")
            .flatMap { try? JSONDecoder().decode([ComposerMentionRecord].self, from: $0) } ?? []
        return ComposerDraft(text: defaults.string(forKey: key) ?? "", mentions: mentions)
    }

    private func save(_ document: ComposerDraft, for key: String) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: key + "_document")
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + "_mentions")
    }
}
