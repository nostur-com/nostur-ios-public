import Testing
@testable import Nostur

@Suite("Short video feed routing")
struct ShortVideoFeedRoutingTests {
    @Test("Profiles include Divine short-video events")
    func profileIncludesShortVideos() {
        #expect(PROFILE_KINDS.contains(34236))
    }

    @Test("Divines removes current short videos from Following")
    func divinesEnabledRemovesShortVideosFromFollowing() {
        let kinds = separateFeedKindsToRemove(
            isDesktopColumns: false,
            pictureFeedEnabled: false,
            yakFeedEnabled: false,
            vineFeedEnabled: true
        )

        #expect(kinds == [34236])
    }

    @Test("Disabling Divines leaves current short videos in Following")
    func divinesDisabledKeepsShortVideosInFollowing() {
        let kinds = separateFeedKindsToRemove(
            isDesktopColumns: false,
            pictureFeedEnabled: false,
            yakFeedEnabled: false,
            vineFeedEnabled: false
        )

        #expect(!kinds.contains(34236))
    }

    @Test("Desktop columns do not apply mobile media-feed routing")
    func desktopColumnsKeepAllMediaKinds() {
        let kinds = separateFeedKindsToRemove(
            isDesktopColumns: true,
            pictureFeedEnabled: true,
            yakFeedEnabled: true,
            vineFeedEnabled: true
        )

        #expect(kinds.isEmpty)
    }
}
