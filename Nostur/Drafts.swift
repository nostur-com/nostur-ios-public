//
//  Drafts.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import Foundation

class Drafts {
    
    static let shared = Drafts()
    
    // This is set when opening a relay feed, with a single relay, to make posting to a single relay easier
    // PostComposer will then show a toggle "Lock post to this relay"
    public var lockToThisRelay: RelayData? = nil
    
    private init() {}
    
    public var draft: String {
        get { UserDefaults.standard.string(forKey: "simple_draft") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "simple_draft") }
    }
    public var restoreDraft: String {
        get { UserDefaults.standard.string(forKey: "undo_send_restore_draft") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "undo_send_restore_draft") }
    }
    
}
