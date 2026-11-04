import CoreData
import XCTest
@testable import Nostur

@MainActor
final class BrowserRelaySettingsTests: XCTestCase {
    func testSnapshotFollowsUnsavedToggleChangesAndDeletion() async throws {
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let managedContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedContext.persistentStoreCoordinator = coordinator
        let entity = try XCTUnwrap(model.entitiesByName["CloudRelay"])
        let relay = CloudRelay(entity: entity, insertInto: managedContext)
        relay.url_ = "wss://relay.example.test"
        relay.auth = true
        let enabled = await BrowserRelaySettings.snapshot(in: managedContext)
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.url, relay.url_)
        XCTAssertEqual(enabled.first?.auth, true)
        relay.auth = false
        let disabled = await BrowserRelaySettings.snapshot(in: managedContext)
        XCTAssertEqual(disabled.first?.auth, false)
        managedContext.delete(relay)
        let deleted = await BrowserRelaySettings.snapshot(in: managedContext)
        XCTAssertTrue(deleted.isEmpty)
    }
}
