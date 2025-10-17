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
    
    public var resumeFeedsSubject = PassthroughSubject<Void, Never>()
    public func resumeFeeds() {
        resumeFeedsSubject.send()
    }
    
    public var pauseFeedsSubject = PassthroughSubject<Void, Never>()
    public func pauseFeeds() {
        pauseFeedsSubject.send()
    }
    
    public var saveFeedStatesSubject = PassthroughSubject<Void, Never>()
    public func saveFeedStates() {
        saveFeedStatesSubject.send()
    }
    
    public var markedAsUnreadSubject = PassthroughSubject<(String, UUID), Never>() // String = nrPost.id, vm.columnVMid
    
    public var notificationNeedsUpdateSubject = PassthroughSubject<NeedsUpdateInfo, Never>()
}

struct NeedsUpdateInfo {
    var event: Event?
    var persistentNotification: PersistentNotification?
}
