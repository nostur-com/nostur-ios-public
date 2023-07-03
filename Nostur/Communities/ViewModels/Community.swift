import Foundation

class Community: Identifiable, Equatable {
    
    let id:String
    var title:String
    var image:String?
    var moderators:[NRContact]
    
    init(id:String, title: String, image: String? = nil, moderators: [NRContact] = []) {
        self.id = id
        self.title = title
        self.image = image
        self.moderators = moderators
    }
    
    static func == (lhs: Community, rhs: Community) -> Bool {
        lhs.id == rhs.id
    }
}
