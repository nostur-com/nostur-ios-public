#if DEBUG
import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite("Feed first-render timing")
struct FeedActionDebugLogTests {
    @Test("Measures the first zero-to-post render")
    func measuresFirstRender() {
        let log = FeedActionDebugLog()
        let start = Date(timeIntervalSince1970: 100)
        log.beginFirstRenderMeasurement(currentPostCount: 0, kind: .firstPosts, at: start)

        log.recordSynchronouslyForTesting("requested older page", at: start.addingTimeInterval(1))
        #expect(log.firstRenderMetric == nil)

        log.recordSynchronouslyForTesting("initial feed · 0→31 posts", at: start.addingTimeInterval(2.31))
        #expect(abs((log.firstRenderMetric?.duration ?? 0) - 2.31) < 0.001)
        #expect(log.firstRenderMetric?.postCount == 31)
        #expect(log.firstRenderMetric?.rating == .slow)
    }

    @Test("Remember feeds measure the first newer insertion, not the restore")
    func measuresFirstUnread() {
        let log = FeedActionDebugLog()
        let start = Date(timeIntervalSince1970: 100)
        log.beginFirstRenderMeasurement(currentPostCount: 0, kind: .firstUnread, at: start)

        log.recordSynchronouslyForTesting("restored feed · 0→102 posts", at: start.addingTimeInterval(0.5))
        #expect(log.firstRenderMetric == nil)

        log.recordSynchronouslyForTesting("inserted 45 newer at top · 102→147", at: start.addingTimeInterval(1.25))
        #expect(abs((log.firstRenderMetric?.duration ?? 0) - 1.25) < 0.001)
        #expect(log.firstRenderMetric?.postCount == 45)
        #expect(log.measurementTitle == "FIRST UNREAD")
        #expect(log.metricCount(45) == "+45 posts")
    }

    @Test("Remember feeds stop measuring when the newer pass is empty")
    func measuresNoNewPosts() {
        let log = FeedActionDebugLog()
        let start = Date(timeIntervalSince1970: 100)
        log.beginFirstRenderMeasurement(currentPostCount: 0, kind: .firstUnread, at: start)

        log.recordSynchronouslyForTesting("restored feed · 0→12 posts", at: start.addingTimeInterval(0.2))
        log.recordSynchronouslyForTesting("initial newer pass finished · no new posts", at: start.addingTimeInterval(1.4))

        #expect(abs((log.firstRenderMetric?.duration ?? 0) - 1.4) < 0.001)
        #expect(log.firstRenderMetric?.outcome == .noNewPosts)
        #expect(log.firstRenderMetric.map(log.metricResult) == "NO NEW POSTS")
        #expect(!log.isMeasuringFirstRender)
    }

    @Test("Remember feeds distinguish a timed-out newer pass")
    func measuresNewerTimeout() {
        let log = FeedActionDebugLog()
        let start = Date(timeIntervalSince1970: 100)
        log.beginFirstRenderMeasurement(currentPostCount: 0, kind: .firstUnread, at: start)

        log.recordSynchronouslyForTesting("initial newer pass timed out", at: start.addingTimeInterval(4.5))

        #expect(log.firstRenderMetric?.outcome == .timedOut)
        #expect(log.firstRenderMetric?.rating == .failed)
        #expect(log.firstRenderMetric.map(log.metricResult) == "CHECK TIMED OUT")
    }

    @Test("Keeps a resume-sized burst instead of dropping prepend lines")
    func keepsResumeBurst() {
        let log = FeedActionDebugLog()
        let start = Date(timeIntervalSince1970: 100)
        for index in 0..<45 {
            log.recordSynchronouslyForTesting("event \(index)", at: start.addingTimeInterval(Double(index) * 0.01))
        }
        #expect(log.entries.count == 45)
        #expect(log.entries.first?.message == "event 0")
        #expect(log.entries.last?.message == "event 44")
    }

    @Test("Uses strict two- and four-second performance thresholds")
    func ratesPerformance() {
        #expect(FeedActionDebugLog.FirstRenderMetric(duration: 1.99, postCount: 1).rating == .fast)
        #expect(FeedActionDebugLog.FirstRenderMetric(duration: 2, postCount: 1).rating == .slow)
        #expect(FeedActionDebugLog.FirstRenderMetric(duration: 3.99, postCount: 1).rating == .slow)
        #expect(FeedActionDebugLog.FirstRenderMetric(duration: 4, postCount: 1).rating == .failed)
    }
}
#endif
