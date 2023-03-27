//
//  Contact+PrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2023.
//

import Foundation

extension Contact {
    var privateNote:PrivateNote? {
        guard let account = NosturState.shared.account else { return nil }
        return account.privateNotes_.first(where: {$0.contact == self })
    }
}
