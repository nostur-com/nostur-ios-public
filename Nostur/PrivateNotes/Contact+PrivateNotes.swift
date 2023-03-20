//
//  Contact+PrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2023.
//

import Foundation

extension Contact {
    var hasPrivateNote:Bool {
        guard let account = NosturState.shared.account else { return false }
        return account.privateNotes_.contains { $0.contact == self }
    }
}
