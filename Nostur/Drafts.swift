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

class Drafts {
    
    static let shared = Drafts()
    
    // This is set when opening a relay feed, with a single relay, to make posting to a single relay easier
    // PostComposer will then show a toggle "Lock post to this relay"
    public var lockToThisRelay: RelayData? = nil
    
    private init() {}
    
    public var draft: String {
        get { UserDefaults.standard.string(forKey: "simple_draft") ?? "" }
        set {
            if newValue != draft {
                draftMentions = []
            }
            UserDefaults.standard.setValue(newValue, forKey: "simple_draft")
        }
    }
    public var restoreDraft: String {
        get { UserDefaults.standard.string(forKey: "undo_send_restore_draft") ?? "" }
        set {
            if newValue != restoreDraft {
                restoreDraftMentions = []
            }
            UserDefaults.standard.setValue(newValue, forKey: "undo_send_restore_draft")
        }
    }

    public var draftMentions: [ComposerMentionRecord] {
        get { mentionRecords(forKey: "simple_draft_mentions") }
        set { setMentionRecords(newValue, forKey: "simple_draft_mentions") }
    }

    public var restoreDraftMentions: [ComposerMentionRecord] {
        get { mentionRecords(forKey: "undo_send_restore_draft_mentions") }
        set { setMentionRecords(newValue, forKey: "undo_send_restore_draft_mentions") }
    }

    func preserveDraftForUndoSend() {
        let mentions = draftMentions
        restoreDraft = draft
        restoreDraftMentions = mentions
    }

    func restoreDraftAfterUndoSend() {
        let mentions = restoreDraftMentions
        draft = restoreDraft
        draftMentions = mentions
        restoreDraft = ""
    }

    private func mentionRecords(forKey key: String) -> [ComposerMentionRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ComposerMentionRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func setMentionRecords(_ records: [ComposerMentionRecord], forKey key: String) {
        guard !records.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    
}
