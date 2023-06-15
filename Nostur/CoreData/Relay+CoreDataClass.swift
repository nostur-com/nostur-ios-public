import Foundation
import CoreData


public class Relay: NSManagedObject {
    @Published var isConnected = false {
        willSet {
            objectWillChange.send()
        }
    }
}
