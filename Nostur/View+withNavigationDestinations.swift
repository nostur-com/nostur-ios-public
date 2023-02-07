//
//  View+withNavigationDestinations.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/02/2023.
//

import Foundation
import SwiftUI

struct NotePath: Hashable {
    var id:String
}

struct ContactPath: Hashable {
    var key:String
}

enum ViewPath: Hashable {
    case Blocklist
    case Following(account:Account)
}

extension View {
    func withNavigationDestinations() -> some View {
        return self
            .navigationDestination(for: NotePath.self) { path in
                NoteById(id: path.id)
            }
            .navigationDestination(for: Event.self) { event in
                NoteDetail(event: event)
            }
            .navigationDestination(for: ContactPath.self) { path in
                ProfileByPubkey(pubkey: path.key)
            }
            .navigationDestination(for: Contact.self) { contact in
                Profile(contact: contact)
            }
            .navigationDestination(for: ViewPath.self) { path in
                switch (path) {
                    case .Blocklist:
                        BlockListView()
                    case .Following(let account):
                        AccountFollowingList(account: account)
                }
            }
    }
}
