import XCTest
@testable import Nostur

@MainActor
final class FollowingPublicKeysSnapshotTests: XCTestCase {
    func testConcurrentBackgroundUpdatesDoNotDelayMainActorRead() async {
        let snapshot = FollowingPublicKeysSnapshot()
        let writersFinished = expectation(description: "Background writers finished")
        let mainActorReadFinished = expectation(description: "Main actor read finished")
        let writerQueue = DispatchQueue(
            label: "com.nostur.tests.following-snapshot",
            attributes: .concurrent
        )
        let writerGroup = DispatchGroup()

        for writer in 0..<8 {
            writerGroup.enter()
            writerQueue.async {
                for iteration in 0..<5_000 {
                    snapshot.value = ["\(writer)-\(iteration)"]
                    _ = snapshot.value.contains("\(writer)-\(iteration)")
                }
                writerGroup.leave()
            }
        }

        DispatchQueue.main.async {
            _ = snapshot.value
            mainActorReadFinished.fulfill()
        }
        await fulfillment(of: [mainActorReadFinished], timeout: 0.5)

        writerGroup.notify(queue: .main) {
            writersFinished.fulfill()
        }
        await fulfillment(of: [writersFinished], timeout: 5.0)
    }
}
