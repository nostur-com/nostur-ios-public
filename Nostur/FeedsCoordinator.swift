//
//  FeedsCoordinator.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import Foundation
import Combine

class FeedsCoordinator {
    
    static let shared = FeedsCoordinator()
    private init() {}
    
    @MainActor
    lazy var fetchScheduler = FeedFetchScheduler()
    
    public var resumeFeedsSubject = PassthroughSubject<Void, Never>()
    public func resumeFeeds() {
        resumeFeedsSubject.send()
        Task { @MainActor in
            self.fetchScheduler.resumeAll()
        }
    }
    
    @MainActor
    var hasMultipleVisibleColumns: Bool {
        fetchScheduler.hasMultipleVisibleColumns
    }
    
    @MainActor
    func registerColumn(_ column: FeedColumnScheduling) {
        fetchScheduler.usesDesktopCollectWindow = IS_DESKTOP_COLUMNS()
        fetchScheduler.register(column)
    }
    
    @MainActor
    func unregisterColumn(_ column: FeedColumnScheduling) {
        fetchScheduler.unregister(column)
    }
    
    @MainActor
    func unregisterColumn(id: UUID) {
        fetchScheduler.unregister(id: id)
    }
    
    @MainActor
    func scheduleNetworkStart(id: UUID, work: @escaping () -> Void) {
        fetchScheduler.scheduleNetworkStart(id: id, work: work)
    }
    
    public var pauseFeedsSubject = PassthroughSubject<Void, Never>()
    public func pauseFeeds() {
        pauseFeedsSubject.send()
    }
    
    public var saveFeedStatesSubject = PassthroughSubject<Void, Never>()
    public func saveFeedStates() {
        saveFeedStatesSubject.send()
    }
    
    public var markedAsReadSubject = PassthroughSubject<(String, UUID), Never>() // String = nrPost.id, vm.columnVMid
    
    
    public var fetchLoopSubject = PassthroughSubject<Void, Never>()
    
    
    
    public var notificationNeedsUpdateSubject = PassthroughSubject<NeedsUpdateInfo, Never>()
}

struct NeedsUpdateInfo {
    var event: Event?
    var persistentNotification: PersistentNotification?
}
