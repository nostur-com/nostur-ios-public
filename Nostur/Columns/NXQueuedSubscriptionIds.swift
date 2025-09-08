//
//  NXQueuedSubscriptionIds.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import Foundation

// For use in NXColumnViewModel.listenForNewPosts()
// When feed is .paused() subscriptionId results are queued
class NXQueuedSubscriptionIds {
    private var queue = Set<String>()
    private let queueLock = NSLock()

    func add(_ ids: Set<String>) {
        queueLock.lock()
        defer { queueLock.unlock() }
        queue.formUnion(ids)
    }

    func getAndClear() -> Set<String> {
        queueLock.lock()
        defer { queueLock.unlock() }
        let result = queue
        queue.removeAll()
        return result
    }
}
