import CoreData
import SwiftUI
import Testing
@testable import Nostur

@MainActor
struct CloudAccountLogoutTests {
    private let pubkey = String(repeating: "ab", count: 32)

    private func makeContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataProvider.shared().container.managedObjectModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    @Test func unnamedAccountUsesNpubAndTracksKeyChanges() throws {
        let context = try makeContext()
        let account = CloudAccount(context: context)
        account.publicKey = pubkey
        let expected = try NIP19(prefix: "npub", hexString: pubkey).displayString
        #expect(account.npub == expected)
        #expect(account.anyName == String(expected.prefix(11)))
        let otherKey = String(repeating: "cd", count: 32)
        account.publicKey = otherKey
        #expect(account.npub == (try NIP19(prefix: "npub", hexString: otherKey).displayString))
    }

    @Test func missingOrMalformedKeyDoesNotCrashNameFallback() throws {
        let context = try makeContext()
        let account = CloudAccount(context: context)
        let keys: [String?] = [nil, "", "invalid", String(repeating: "z", count: 64)]
        for key in keys {
            account.publicKey_ = key
            #expect(account.npub.isEmpty)
            #expect(account.anyName.isEmpty)
        }
        account.name = "Named account"
        #expect(account.anyName == "Named account")
    }

    @Test func retainedAccountSurvivesDeletionBeforeFirstNpubAccess() throws {
        let context = try makeContext()
        let account = CloudAccount(context: context)
        account.publicKey = pubkey
        try context.save()
        // Reproduce logout before the lazy name fallback has ever been evaluated.
        context.delete(account)
        #expect(account.isDeleted)
        #expect(account.npub.isEmpty)
        try context.save()
        #expect(account.managedObjectContext == nil)
        #expect(account.anyName.isEmpty)
        #expect(account.npub.isEmpty)
        // SwiftUI can still evaluate a retained observed row after the delete/save.
        _ = AccountRow(account: account).body
    }
}
