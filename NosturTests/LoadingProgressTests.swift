import Foundation
import Testing
@testable import Nostur

@Suite("Feed loading progress")
@MainActor
struct LoadingProgressTests {
    @Test("Connection waiting remains connecting until a request starts")
    func connectionAndRequestPhasesStayDistinct() {
        let progress = NXSpeedTest()
        progress.timestampStart = Date()

        progress.waitingForConnection()
        #expect(progress.loadingBarViewState == .connecting)

        progress.requestStarted()
        #expect(progress.loadingBarViewState == .fetching)
    }

    @Test("A repeated connection signal cannot regress an active request")
    func connectionSignalDoesNotRegressFetching() {
        let progress = NXSpeedTest()
        progress.timestampStart = Date()
        progress.requestStarted()

        progress.waitingForConnection()
        #expect(progress.loadingBarViewState == .fetching)
    }
}
