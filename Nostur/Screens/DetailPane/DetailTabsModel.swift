import SwiftUI

final class DetailTabsModel: ObservableObject {
    
    static public let shared = DetailTabsModel()
    
    @Published var tabs:[Tab] = []
    @Published var selected:Tab? = nil
    
    struct Tab: Identifiable, Equatable {
        var id:UUID
        var notePath:NotePath?
        var contactPath:ContactPath?
        var event:Event?
        var nrPost:NRPost?
        var contact:Contact?
        
        init(notePath:NotePath? = nil, contactPath:ContactPath? = nil, event:Event? = nil, contact:Contact? = nil, nrPost:NRPost? = nil) {
            self.id = UUID()
            self.notePath = notePath
            self.contactPath = contactPath
            self.event = event
            self.contact = contact
            self.nrPost = nrPost
            
            if (contactPath != nil) {
                if let contactFromCache = Contact.fetchByPubkey(contactPath!.key, context: DataProvider.shared().container.viewContext) {
                    self.contact = contactFromCache
                }
            }
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.id == rhs.id
        }
    }
}
