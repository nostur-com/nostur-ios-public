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

    @Test("Jump reports keep only the preceding ten seconds and include diagnostic context")
    func jumpReportWindow() {
        let log = FeedActionDebugLog()
        let now = Date(timeIntervalSince1970: 100)
        log.recordSynchronouslyForTesting("stale event", at: now.addingTimeInterval(-11))
        log.recordSynchronouslyForTesting("boundary event", at: now.addingTimeInterval(-10))
        log.recordSynchronouslyForTesting("prepend before jump", at: now.addingTimeInterval(-1))
        let report = log.jumpReport(feedName: "Following", currentState: "anchor abc · y 123", at: now)
        #expect(!report.contains("stale event"))
        #expect(report.contains("boundary event"))
        #expect(report.contains("prepend before jump"))
        #expect(report.contains("Following"))
        #expect(report.contains("anchor abc · y 123"))
        #expect(report.contains("TEST_BUILD_ID"))
        #expect(report.contains("Platform:"))
        #expect(!log.jumpReport(feedName: "Following", currentState: "idle", at: now.addingTimeInterval(20)).contains("prepend before jump"))
        log.clear()
        #expect(!log.jumpReport(feedName: "Following", currentState: "idle", at: now).contains("boundary event"))
    }

    @Test("Jump capture includes deferred actions and bounds a busy feed burst")
    func jumpReportBurst() {
        let log = FeedActionDebugLog()
        let now = Date(timeIntervalSince1970: 100)
        for index in 0..<350 {
            log.recordSynchronouslyForTesting("burst-\(index) end", at: now)
        }
        // Production events are deferred for the overlay but available immediately to capture.
        log.record("just before capture", at: now)
        let report = log.jumpReport(feedName: "Following", currentState: "idle", at: now)
        #expect(report.contains("300 actions"))
        #expect(!report.contains("burst-50 end"))
        #expect(report.contains("burst-51 end"))
        #expect(report.contains("burst-349 end"))
        #expect(report.contains("just before capture"))
        #expect(log.entries.count == 60)
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
