//
//  Event+PrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2023.
//

import Foundation

extension Event {
    var hasPrivateNote:Bool {
        guard let account = NosturState.shared.account else { return false }
        return account.privateNotes_.contains { $0.post == self }
    }
}
