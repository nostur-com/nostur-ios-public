import XCTest
@testable import Nostur

@MainActor
final class EmbeddedAudioPreviewTests: XCTestCase {
    func testLiveMP3ImmediatelyOffersPlayback() {
        assertAudioOffersPlayback("https://stream.bowlafterbowl.com/listen/bowlafterbowl/stream.mp3")
    }

    func testM4AImmediatelyOffersPlayback() {
        assertAudioOffersPlayback("https://example.com/episode.m4a")
    }

    func testAudioPreservesLowDataWarning() {
        let previousLowDataMode = SettingsStore.shared.lowDataMode
        defer { SettingsStore.shared.lowDataMode = previousLowDataMode }
        SettingsStore.shared.lowDataMode = true
        let url = URL(string: "https://example.com/live.mp3")!
        let vm = EmbeddedVideoVM()

        vm.load(url)

        guard case .lowDataMode(let value) = vm.viewState else {
            return XCTFail("Audio should still respect low data mode")
        }
        XCTAssertEqual(value, url.absoluteString)
    }

    func testAudioPreservesHTTPWarning() {
        let url = URL(string: "http://example.com/live.mp3")!
        let vm = EmbeddedVideoVM()

        vm.load(url)

        guard case .noHttpsWarning(let value) = vm.viewState else {
            return XCTFail("Audio should still require permission for HTTP")
        }
        XCTAssertEqual(value, url.absoluteString)
    }

    private func assertAudioOffersPlayback(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let previousLowDataMode = SettingsStore.shared.lowDataMode
        defer { SettingsStore.shared.lowDataMode = previousLowDataMode }
        SettingsStore.shared.lowDataMode = false
        let vm = EmbeddedVideoVM()

        vm.load(URL(string: value)!)

        XCTAssertTrue(vm.isAudio, file: file, line: line)
        guard case .noPreviewFound(let playbackURL) = vm.viewState else {
            return XCTFail("Audio must offer Play without waiting for a preview download", file: file, line: line)
        }
        XCTAssertEqual(playbackURL, value, file: file, line: line)
        XCTAssertEqual(vm.downloadProgress, 0, file: file, line: line)
    }
}
