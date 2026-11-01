import XCTest
import CoreData
import Nuke
@testable import Nostur

@MainActor
final class BackgroundCrashSafetyTests: XCTestCase {
    func testMalformedIndexedEventTagsStayPlainText() {
        for value in ["", "bad-id", String(repeating: "z", count: 64)] {
            let tag: FastTag = ("e", value, nil, nil, nil, nil, nil, nil, nil, nil)
            let result = NRTextParser.shared.copyPasteText(fastTags: [tag], text: "See #[0]")
            XCTAssertEqual(result.text, "See #[0]")
        }
    }

    func testValidIndexedEventTagUsesNotePrefix() throws {
        let id = String(repeating: "a", count: 64)
        let tag: FastTag = ("e", id, nil, nil, nil, nil, nil, nil, nil, nil)
        let note = try NIP19(prefix: "note", hexString: id).displayString
        let result = NRTextParser.shared.copyPasteText(fastTags: [tag], text: "See #[0]")
        XCTAssertEqual(result.text, "See @\(note.prefix(11))")
    }

    func testDiskCacheFailureLeavesPipelineUsableWithoutDiskCache() {
        var configuration = ImagePipeline.Configuration()
        configuration.dataCache = ImageProcessing.makeDataCache(name: "unavailable", sizeLimit: 1024) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        let pipeline = ImagePipeline(configuration: configuration)
        XCTAssertNil(pipeline.configuration.dataCache)
        XCTAssertNotNil(pipeline.configuration.imageCache)
    }

    func testCleanupDoesNotDeleteWhenPreservationFetchFails() throws {
        for entity in ["CloudAccount", "Bookmark", "CloudPrivateNote"] {
            let (context, store) = try makeFailingStore(entity: entity)
            defer { store.removeIdentifierFile() }
            XCTAssertThrowsError(try Maintenance.databaseCleanUp(context))
            XCTAssertEqual(store.executedWrites, 0, entity)
        }
    }

    func testFailedMigrationDoesNotRecordCompletion() throws {
        let (context, store) = try makeFailingStore(entity: "CloudAccount")
        defer { store.removeIdentifierFile() }
        Maintenance.runFixImposterFalsePositivesAgainAgain(context: context)
        XCTAssertTrue(store.fetchedEntities.contains("CloudAccount"))
        XCTAssertTrue(context.insertedObjects.isEmpty)
        XCTAssertEqual(store.executedWrites, 0)
    }
}

private func makeFailingStore(entity: String) throws -> (NSManagedObjectContext, FailingMaintenanceStore) {
    let type = "FailingMaintenanceStore"
    NSPersistentStoreCoordinator.registerStoreClass(FailingMaintenanceStore.self, forStoreType: type)
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataProvider.shared().container.managedObjectModel)
    // A nil URL traps inside addPersistentStore on this SDK. The file is only an identifier.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("nostur-failing-store-\(UUID().uuidString)")
    guard let store = try coordinator.addPersistentStore(ofType: type, configurationName: nil, at: url) as? FailingMaintenanceStore else {
        throw CocoaError(.persistentStoreOperation)
    }
    store.failingEntity = entity
    store.identifierURL = url
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return (context, store)
}

@objc(FailingMaintenanceStore)
private final class FailingMaintenanceStore: NSIncrementalStore {
    var failingEntity = ""
    var executedWrites = 0
    var fetchedEntities: [String] = []
    var identifierURL: URL?

    func removeIdentifierFile() {
        guard let identifierURL else { return }
        try? FileManager.default.removeItem(at: identifierURL)
    }

    override func loadMetadata() throws {
        metadata = [NSStoreUUIDKey: UUID().uuidString, NSStoreTypeKey: "FailingMaintenanceStore"]
    }

    override func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext?) throws -> Any {
        if let fetch = request as? NSFetchRequest<NSFetchRequestResult> {
            let name = fetch.entityName ?? fetch.entity?.name ?? ""
            fetchedEntities.append(name)
            if name == failingEntity { throw CocoaError(.persistentStoreOperation) }
            // context.count expects an array whose first value is the count.
            if fetch.resultType == .countResultType { return [NSNumber(value: 0)] }
            return []
        }
        executedWrites += 1
        throw CocoaError(.persistentStoreOperation)
    }

    override func obtainPermanentIDs(for array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        executedWrites += 1
        throw CocoaError(.persistentStoreOperation)
    }
}
