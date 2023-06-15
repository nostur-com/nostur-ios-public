import Foundation
import CoreData


extension MutedWords {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MutedWords> {
        return NSFetchRequest<MutedWords>(entityName: "MutedWords")
    }

    @NSManaged public var words: String?
    @NSManaged public var enabled: Bool

}

extension MutedWords : Identifiable {

}
