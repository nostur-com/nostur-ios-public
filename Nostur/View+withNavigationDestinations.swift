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
    }
}
