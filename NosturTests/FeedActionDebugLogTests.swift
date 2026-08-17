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
        log.beginFirstRenderMeasurement(currentPostCount: 0, at: start)

        log.record("requested older page", at: start.addingTimeInterval(1))
        #expect(log.firstRenderMetric == nil)

        log.record("initial feed · 0→31 posts", at: start.addingTimeInterval(2.31))
        #expect(abs((log.firstRenderMetric?.duration ?? 0) - 2.31) < 0.001)
        #expect(log.firstRenderMetric?.postCount == 31)
        #expect(log.firstRenderMetric?.rating == .slow)
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
