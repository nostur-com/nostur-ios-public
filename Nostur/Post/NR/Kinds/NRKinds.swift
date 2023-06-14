import Foundation

struct KindFileMetadata {
    var url:String
    var m:String?
    var hash:String?
    var dim:String?
    var blurhash:String?
}

struct KindHightlight {
    var highlightAuthorPubkey:String?
    var highlightAuthorPicture:String?
    var highlightAuthorIsFollowing:Bool
    var highlightAuthorName:String?
    var highlightUrl:String?
    var highlightNrContact: NRContact?
}
