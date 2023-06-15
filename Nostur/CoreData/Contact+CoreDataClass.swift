import Foundation
import CoreData
import Combine

public class Contact: NSManagedObject {
    var contactUpdated = PassthroughSubject<Contact, Never>()
    var nip05updated = PassthroughSubject<Bool, Never>()
}
