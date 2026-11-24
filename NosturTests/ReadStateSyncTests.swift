import Combine
import CoreData
import XCTest
@testable import Nostur

@MainActor
final class ReadStateSyncTests: XCTestCase {
    private let ourKey = String(repeating: "ab", count: 32)
    private let otherKey = String(repeating: "cd", count: 32)

    private func makeContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataProvider.shared().container.managedObjectModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    private func makeAccount(_ context: NSManagedObjectContext) -> CloudAccount {
        let account = CloudAccount(context: context)
        account.publicKey = ourKey
        account.lastSeenPostCreatedAt = 100
        account.lastSeenReactionCreatedAt = 110
        account.lastSeenZapCreatedAt = 120
        account.lastSeenRepostCreatedAt = 130
        return account
    }

    private func makeConversation(_ context: NSManagedObjectContext, account: String? = nil) -> CloudDMState {
        let key = account ?? ourKey
        return CloudDMState.create(accountPubkey: key, participants: [ourKey, otherKey], context: context)
    }

    func testReadProgressSurvivesOlderCloudValuesAndRestart() throws {
        let context = try makeContext()
        let account = makeAccount(context)
        let conversation = makeConversation(context)
        conversation.markedReadAt_ = Date(timeIntervalSince1970: 200)
        let suite = "ReadStateSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstRun = ReadStateSync(context: context, defaults: defaults)
        firstRun.reconcile([account, conversation])
        try context.save()

        // Simulate an older offline device overwriting the cloud record.
        account.lastSeenPostCreatedAt = 1
        account.lastSeenReactionCreatedAt = 2
        account.lastSeenZapCreatedAt = 3
        account.lastSeenRepostCreatedAt = 4
        conversation.markedReadAt_ = Date(timeIntervalSince1970: 5)
        let secondRun = ReadStateSync(context: context, defaults: defaults)
        secondRun.refresh()
        XCTAssertEqual(account.lastSeenPostCreatedAt, 100)
        XCTAssertEqual(account.lastSeenReactionCreatedAt, 110)
        XCTAssertEqual(account.lastSeenZapCreatedAt, 120)
        XCTAssertEqual(account.lastSeenRepostCreatedAt, 130)
        XCTAssertEqual(conversation.markedReadAt_, Date(timeIntervalSince1970: 200))

        account.lastSeenPostCreatedAt = 300
        conversation.markedReadAt_ = Date(timeIntervalSince1970: 400)
        secondRun.refresh()
        XCTAssertEqual(account.lastSeenPostCreatedAt, 300)
        XCTAssertEqual(conversation.markedReadAt_, Date(timeIntervalSince1970: 400))
    }

    func testReadStateIsScopedToAccountAndConversation() throws {
        let context = try makeContext()
        let account = makeAccount(context)
        let otherAccount = CloudAccount(context: context)
        otherAccount.publicKey = otherKey
        let ourConversation = makeConversation(context)
        ourConversation.markedReadAt_ = Date(timeIntervalSince1970: 200)
        let otherConversation = makeConversation(context, account: otherKey)
        let thirdConversation = CloudDMState.create(
            accountPubkey: ourKey, participants: [ourKey, String(repeating: "ef", count: 32)], context: context
        )
        let suite = "ReadStateSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ReadStateSync(context: context, defaults: defaults)
        sync.reconcile([account, ourConversation])
        sync.reconcile([otherAccount, otherConversation, thirdConversation])
        XCTAssertEqual(otherAccount.lastSeenPostCreatedAt, 0)
        XCTAssertNil(otherConversation.markedReadAt_)
        XCTAssertNil(thirdConversation.markedReadAt_)
    }

    func testRunningAppPublishesImportedReadStateWithoutRestart() async throws {
        let context = try makeContext()
        let account = makeAccount(context)
        let conversation = makeConversation(context)
        try context.save()
        let accountID = account.objectID
        let conversationID = conversation.objectID
        let suite = "ReadStateSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ReadStateSync(context: context, defaults: defaults)
        sync.start()
        let notificationModel = NotificationsViewModel()
        notificationModel.bindReadState(to: account, sync: sync)
        let oldSnapshot = account.toStruct()
        XCTAssertTrue(notificationModel.isReadSnapshotCurrent(oldSnapshot))
        let merged = expectation(description: "Running app observes read progress imported from another device")
        merged.assertForOverFulfill = false
        let token = sync.changedAccounts.sink { keys in
            if keys.contains(self.ourKey), account.lastSeenPostCreatedAt == 900,
               account.lastSeenReactionCreatedAt == 900, account.lastSeenZapCreatedAt == 900,
               conversation.markedReadAt_ == Date(timeIntervalSince1970: 900) {
                merged.fulfill()
            }
        }
        defer { token.cancel() }
        let importer = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        importer.persistentStoreCoordinator = context.persistentStoreCoordinator
        try await importer.perform {
            let importedAccount = try XCTUnwrap(importer.existingObject(with: accountID) as? CloudAccount)
            importedAccount.lastSeenPostCreatedAt = 900
            importedAccount.lastSeenReactionCreatedAt = 900
            importedAccount.lastSeenZapCreatedAt = 900
            let importedConversation = try XCTUnwrap(importer.existingObject(with: conversationID) as? CloudDMState)
            importedConversation.markedReadAt_ = Date(timeIntervalSince1970: 900)
            try importer.save()
        }
        await fulfillment(of: [merged], timeout: 3)
        XCTAssertFalse(notificationModel.isReadSnapshotCurrent(oldSnapshot))
        XCTAssertTrue(notificationModel.isReadSnapshotCurrent(account.toStruct()))
    }

    func testNotificationRecountsAreRejectedDuringMergeAndAccountSwitch() throws {
        let context = try makeContext()
        let account = makeAccount(context)
        let suite = "ReadStateSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ReadStateSync(context: context, defaults: defaults)
        let model = NotificationsViewModel()
        model.bindReadState(to: account, sync: sync)
        let oldSnapshot = account.toStruct()
        account.lastSeenPostCreatedAt = 900
        // Even before the change observer runs, an old recount must be rejected.
        XCTAssertFalse(model.isReadSnapshotCurrent(oldSnapshot))
        sync.reconcile([account])
        XCTAssertTrue(model.isReadSnapshotCurrent(account.toStruct()))
        let switchedAccount = CloudAccount(context: context)
        switchedAccount.publicKey = otherKey
        model.bindReadState(to: switchedAccount, sync: sync)
        XCTAssertFalse(model.isReadSnapshotCurrent(account.toStruct()))
        XCTAssertTrue(model.isReadSnapshotCurrent(switchedAccount.toStruct()))
    }

    func testBackgroundMentionsWorkBeforeModelLoadsAndRejectReadOnAnotherDevice() throws {
        let context = try makeContext()
        let account = makeAccount(context)
        let model = NotificationsViewModel()
        let snapshot = account.toStruct()
        XCTAssertTrue(model.isBackgroundMentionSnapshotCurrent(snapshot, in: context))
        account.lastSeenPostCreatedAt = 900
        XCTAssertFalse(model.isBackgroundMentionSnapshotCurrent(snapshot, in: context))
    }

    func testDMReadIsSavedWithoutWaitingForBusyImporter() async throws {
        let context = try makeContext()
        let conversation = makeConversation(context)
        try context.save()
        let id = conversation.objectID
        let importer = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        importer.persistentStoreCoordinator = context.persistentStoreCoordinator
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            importer.perform {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let readAt = Date(timeIntervalSince1970: 200)
        let began = Date()
        conversation.markRead(at: readAt)
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.1)
        // Drain only the main context. The importer remains held throughout.
        await context.perform {}
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let saved = try XCTUnwrap(reader.existingObject(with: id) as? CloudDMState)
        XCTAssertEqual(saved.markedReadAt_, readAt)
        conversation.markRead(at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(conversation.markedReadAt_, readAt)
    }

    func testNotificationMarkReadReturnsWhileImporterIsBusyAndSavesOwningContext() async throws {
        let context = try makeContext()
        let account = makeAccount(context)
        try context.save()
        let suite = "ReadStateSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = ReadStateSync(context: context, defaults: defaults)
        let model = NotificationsViewModel()
        model.bindReadState(to: account, sync: sync)
        model.unreadMentions_ = 9
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            bg().perform {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let saved = expectation(description: "Read marker saved in the account's owning context")
        saved.assertForOverFulfill = false
        let token = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)
            .sink { _ in
                if account.lastSeenPostCreatedAt > 100 { saved.fulfill() }
            }
        defer { token.cancel() }
        let began = Date()
        model.markMentionsAsRead()
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.1)
        XCTAssertEqual(model.unreadMentions, 0)
        release.signal()
        await fulfillment(of: [saved], timeout: 3)
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let persisted = try XCTUnwrap(reader.existingObject(with: account.objectID) as? CloudAccount)
        XCTAssertEqual(persisted.lastSeenPostCreatedAt, account.lastSeenPostCreatedAt)
    }

    func testLateDMRecountUsesNewReadPositionAndKeepsNewMessagesUnread() async throws {
        let context = try makeContext()
        let conversation = makeConversation(context)
        conversation.markedReadAt_ = Date(timeIntervalSince1970: 100)
        for (index, timestamp) in [150, 200, 300].enumerated() {
            let message = Event(context: context)
            message.id = String(repeating: String(index + 1), count: 64)
            message.kind = index == 0 ? 4 : 14
            message.pubkey = otherKey
            message.created_at = Int64(timestamp)
            message.groupId = conversation.conversationId
        }
        try context.save()
        let importer = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        importer.persistentStoreCoordinator = context.persistentStoreCoordinator
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            importer.perform {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let recount = Task { @MainActor in await conversation.getUnread(in: importer) }
        // Let the recount capture the old read position before the cloud update.
        await Task.yield()
        conversation.markRead(at: Date(timeIntervalSince1970: 200))
        release.signal()
        let unread = await recount.value
        XCTAssertEqual(unread, 1)
        XCTAssertEqual(conversation.cachedViewUnread, 1)
    }
}
