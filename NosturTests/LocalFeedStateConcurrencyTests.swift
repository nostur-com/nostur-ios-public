import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite("Local feed state concurrency", .serialized)
struct LocalFeedStateConcurrencyTests {
    private func state(_ value: String) -> LocalFeedState {
        LocalFeedState(cloudFeedId: "feed", onScreenIds: [value], parentIds: [value])
    }

    @Test("Maintenance snapshots remain consistent during UI updates")
    func concurrentSnapshots() async {
        let manager = LocalFeedStateManager(initialStates: LocalFeedStates(localFeedStates: [state("original")]))
        let originalSnapshot = manager.getFeedStates()
        let readers = (0..<4).map { _ in
            Task.detached {
                for _ in 0..<10_000 {
                    let snapshot = manager.getFeedStates()
                    #expect(snapshot.count == 1)
                    if let feed = snapshot.first {
                        #expect(Set(feed.onScreenIds) == feed.parentIds)
                    }
                }
            }
        }
        for index in 0..<2_000 {
            manager.updateFeedState(state(String(index)))
        }
        for reader in readers {
            await reader.value
        }
        #expect(originalSnapshot.first?.onScreenIds == ["original"])
        #expect(manager.getFeedStates().first?.onScreenIds == ["1999"])
    }

    @Test("UI state updates complete while the importer context is held")
    func updateDoesNotWaitForImports() async {
        let manager = LocalFeedStateManager(initialStates: LocalFeedStates(localFeedStates: []))
        let releaseImport = DispatchSemaphore(value: 0)
        defer { releaseImport.signal() }

        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            bg().perform {
                started.resume()
                _ = releaseImport.wait(timeout: .now() + 5)
            }
        }

        let start = Date()
        manager.updateFeedState(state("visible"))
        let snapshot = manager.getFeedStates()
        #expect(Date().timeIntervalSince(start) < 0.1)
        #expect(snapshot.first?.onScreenIds == ["visible"])
    }
}
