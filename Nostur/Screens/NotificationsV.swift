//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI

struct NotificationsV: View {
    
    @EnvironmentObject var ns:NosturState
//    @State var reactions:[Event] = []
    
    var body: some View {
        DynamicFetchView(predicate: NSPredicate(format: "kind == 7 AND tagsSerialized CONTAINS %@", ns.account!.publicKey!), sortDescriptors: []) { (events: FetchedResults<Event>) in
            List {
                ForEach(events) {
                    NoteRowView(event: $0)
                }
            }
            
        }
    }
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsV()
            .withPreviewEnvironment()
    }
}
