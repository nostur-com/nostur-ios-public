import Foundation

struct PostActionNotification {
    let type:ActionType
    let eventId:String
    
    var bookmarked:Bool = false
    var hasPrivateNote:Bool = false
    
    enum ActionType {
        case bookmark
        case liked
        case reposted
        case replied
        case privateNote
    }
}
