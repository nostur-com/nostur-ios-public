import AVFoundation
import CryptoKit
import NostrEssentials
import Testing
import UIKit
@testable import Nostur

@Suite(.serialized)
struct VideoPreparationTests {
    @Test func automaticSizesLargeVideosWithoutUpscalingSmallOnes() {
        #expect(VideoUploadQuality.automatic.outputSize(for: CGSize(width: 3840, height: 2160), shortVideo: false) == CGSize(width: 1920, height: 1080))
        #expect(VideoUploadQuality.automatic.outputSize(for: CGSize(width: 2160, height: 3840), shortVideo: false) == CGSize(width: 1080, height: 1920))
        #expect(VideoUploadQuality.automatic.outputSize(for: CGSize(width: 1080, height: 2400), shortVideo: false) == CGSize(width: 864, height: 1920))
        #expect(VideoUploadQuality.automatic.outputSize(for: CGSize(width: 640, height: 360), shortVideo: false) == CGSize(width: 640, height: 360))
        #expect(VideoUploadQuality.higher.outputSize(for: CGSize(width: 3840, height: 2160), shortVideo: false) == CGSize(width: 3840, height: 2160))
        #expect(VideoUploadQuality.automatic.outputSize(for: CGSize(width: 1920, height: 1080), shortVideo: true) == CGSize(width: 1280, height: 720))
        #expect(VideoUploadQuality.automatic.bitRate(size: CGSize(width: 1920, height: 1080), fps: 30, sourceBitRate: 30_000_000) == 6_220_800)
        #expect(VideoUploadQuality.automatic.bitRate(size: CGSize(width: 640, height: 360), fps: 30, sourceBitRate: 400_000) == 400_000)
        #expect(VideoUploadQuality.automatic.outputFrameRate(24) == 24)
        #expect(VideoUploadQuality.automatic.outputFrameRate(60) == 60)
        #expect(VideoUploadQuality.automatic.outputFrameRate(120) == 60)
        #expect(VideoUploadQuality.smaller.outputFrameRate(60) == 30)
        #expect(VideoUploadQuality.smaller.bitRate(size: CGSize(width: 640, height: 360), fps: 30, sourceBitRate: 400_000) == 240_000)
    }

    @Test(arguments: VideoUploadQuality.allCases)
    func sourcePersonalMetadataIsRejectedButEncodedOutputIsClean(quality: VideoUploadQuality) async throws {
        let source = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let originalBytes = try Data(contentsOf: source)
        #expect(originalBytes.range(of: Data("PrivateAuthorSentinel".utf8)) != nil)
        do {
            try await VideoPreparation.verifyPrivacy(of: source)
            Issue.record("The original file must not pass the upload privacy check")
        } catch VideoPreparationError.unsafeMetadata { }
        let prepared = try await VideoPreparation.prepare(inputURL: source, quality: quality)
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        try await VideoPreparation.verifyPrivacy(of: prepared.url)
        let bytes = try Data(contentsOf: prepared.url)
        for value in ["PrivateAuthorSentinel", "PrivateDeviceSentinel", "+52.3702+004.8952/", "2020-01-02T03:04:05Z"] {
            #expect(bytes.range(of: Data(value.utf8)) == nil)
        }
        #expect(prepared.url != source)
        #expect(try Data(contentsOf: source) == originalBytes)
        #expect(prepared.sha256 == CryptoKit.SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        #expect(prepared.byteCount == bytes.count)
        let asset = AVURLAsset(url: prepared.url)
        let tracks = try await asset.load(.tracks)
        #expect(tracks.count == 1)
        let descriptions = try await tracks[0].load(.formatDescriptions)
        #expect(CMFormatDescriptionGetMediaSubType(try #require(descriptions.first)) == kCMVideoCodecType_H264)
        // Network-optimized output puts metadata before the media payload.
        #expect(try #require(bytes.range(of: Data("moov".utf8))).lowerBound < #require(bytes.range(of: Data("mdat".utf8))).lowerBound)
    }

    @Test func shortVideoPreservesRotationAndUsesExactTrimmedDuration() async throws {
        let source = try await makeVideo(rotated: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try await VideoPreparation.prepare(inputURL: source, shortVideo: true, start: 0.5, end: 1.5, muted: true)
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        #expect(prepared.dimensions == CGSize(width: 32, height: 64))
        let asset = AVURLAsset(url: prepared.url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.08)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == prepared.dimensions)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        try await VideoPreparation.verifyPrivacy(of: prepared.url)
    }

    @Test @MainActor func preparedShortVideoIsReusedAndFailureRetainsAttachment() async throws {
        let source = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try await videoFileWork { try await VideoPreparation.prepare(inputURL: source, shortVideo: true) }
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        let video = PostedVideoMeta(index: 0, videoURL: prepared.url, preparedVideo: prepared)
        let first = try #require(await prepareComposerVideoData(video, shortVideo: true))
        let second = try #require(await prepareComposerVideoData(video, shortVideo: true))
        #expect(first.0 == prepared.url && second.0 == prepared.url)
        #expect(first.1 == second.1)
        let missing = PostedVideoMeta(index: 1, videoURL: URL(fileURLWithPath: "/nonexistent/video.mov"))
        let model = TypingTextModel()
        model.pastedVideos = [video, missing]
        let result = await prepareUploadItems(pubkey: String(repeating: "0", count: 64), videos: model.pastedVideos,
                                             typingTextModel: model, isVineVideoPost: true, uploadMethod: .blossom)
        #expect(result.isEmpty)
        #expect(model.pastedVideos.count == 2)
        #expect(missing.uploadState.isFailed)
    }

    @Test func cancelledPreparationDoesNotReturnAnUploadableFile() async throws {
        let source = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let task = Task {
            try Task.checkCancellation()
            return try await VideoPreparation.prepare(inputURL: source)
        }
        task.cancel()
        do {
            let unexpected = try await task.value
            try? FileManager.default.removeItem(at: unexpected.url)
            Issue.record("Cancelled preparation must not return a file")
        } catch is CancellationError { }
    }

    @Test func cancellingAnActiveEncodeFinishesPromptly() async throws {
        let source = try await makeVideo(size: CGSize(width: 2048, height: 1152), frameCount: 60)
        defer { try? FileManager.default.removeItem(at: source) }
        let (progress, updates) = AsyncStream<Double>.makeStream()
        let worker = Task {
            defer { updates.finish() }
            return try await VideoPreparation.prepare(inputURL: source) { fraction in updates.yield(fraction) }
        }
        for await _ in progress { break }
        let cancelledAt = Date()
        worker.cancel()
        do {
            let unexpected = try await worker.value
            try? FileManager.default.removeItem(at: unexpected.url)
            Issue.record("An active encode must honor cancellation")
        } catch is CancellationError { }
        #expect(Date().timeIntervalSince(cancelledAt) < 2)
    }

    @Test @MainActor func cancellingUploadInvalidatesCallbacksAndKeepsAttachments() {
        let model = NewPostModel()
        let video = PostedVideoMeta(index: 0, videoURL: URL(fileURLWithPath: "/nonexistent/video.mov"))
        model.typingTextModel.pastedVideos = [video]
        video.uploadState = .preparing
        model.typingTextModel.uploading = true
        model.typingTextModel.sending = true
        let attempt = model.videoPostAttemptID
        model.cancelVideoPostUpload()
        #expect(model.videoPostAttemptID != attempt)
        #expect(model.typingTextModel.pastedVideos.first?.id == video.id)
        #expect(video.uploadState == .idle)
        #expect(!model.typingTextModel.uploading && !model.typingTextModel.sending)
    }

    @Test func multipartUsesExactSignedBytesAndNeverIncludesSourceFilename() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("PrivateFamilyHoliday.mov")
        let data = Data(repeating: 42, count: 2_100_000)
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let body = try VideoMultipartBody.make(file: source, contentType: "video/mp4", boundary: "test-boundary")
        defer { try? FileManager.default.removeItem(at: body) }
        let bytes = try Data(contentsOf: body)
        let expected = NostrEssentials.makeHttpBody(mediaData: data, contentType: "video/mp4", filename: "media.mp4", boundary: "test-boundary")
        #expect(bytes == expected)
        #expect(try VideoPreparation.hashFile(body) == CryptoKit.SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        #expect(bytes.range(of: Data(source.lastPathComponent.utf8)) == nil)
    }

    @Test func oversizedAndAuthorizationFailuresRemainDistinct() throws {
        for code in [413, 401, 403, 500] {
            let response = HTTPURLResponse(url: URL(string: "https://example.com/upload")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            do { try PostVideoUploadError.check(response); Issue.record("Expected upload failure") }
            catch let error as PostVideoUploadError {
                switch (code, error) {
                case (413, .tooLarge), (401, .unauthorized), (403, .unauthorized), (500, .rejected(500)): break
                default: Issue.record("Unexpected error for HTTP \(code)")
                }
            }
        }
    }

    @Test func audioSurvivesTrimmingUnlessMuteIsSelected() async throws {
        let video = try await makeVideo()
        let wave = TemporaryMediaFiles.shared.makeURL(extension: "wav")
        let source = TemporaryMediaFiles.shared.makeURL(extension: "mov")
        defer { for url in [video, wave, source] { try? FileManager.default.removeItem(at: url) } }
        let samples = Data(repeating: 0, count: 44_100 * 2 * 2 * 2)
        var wav = Data("RIFF".utf8)
        func append32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) } }
        append32(UInt32(samples.count + 36))
        wav.append(Data("WAVEfmt ".utf8)); append32(16); append16(1); append16(2)
        append32(44_100); append32(176_400); append16(4); append16(16)
        wav.append(Data("data".utf8)); append32(UInt32(samples.count)); wav.append(samples)
        try wav.write(to: wave)
        let composition = AVMutableComposition()
        for (url, type) in [(video, AVMediaType.video), (wave, AVMediaType.audio)] {
            let asset = AVURLAsset(url: url)
            let sourceTrack = try #require(try await asset.loadTracks(withMediaType: type).first)
            let track = try #require(composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid))
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: sourceTrack, at: .zero)
        }
        let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        exporter.outputURL = source
        exporter.outputFileType = .mov
        await exporter.export()
        #expect(exporter.status == .completed)
        for muted in [false, true] {
            let prepared = try await VideoPreparation.prepare(inputURL: source, shortVideo: true, start: 0.5, end: 1.5, muted: muted)
            defer { try? FileManager.default.removeItem(at: prepared.url) }
            let asset = AVURLAsset(url: prepared.url)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            #expect(audio.count == (muted ? 0 : 1))
            if let track = audio.first {
                let formats = try await track.load(.formatDescriptions)
                let format = try #require(formats.first)
                #expect(CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC)
                #expect(abs((try await track.load(.timeRange)).duration.seconds - 1) < 0.1)
            }
            try await VideoPreparation.verifyPrivacy(of: prepared.url)
        }
    }

    @Test func realTenBitHLGInputExportsSDRWithoutSourceMetadata() async throws {
        let fixture = try #require(Bundle(for: VideoPreparationTestBundle.self).url(forResource: "hlg-10bit", withExtension: "mov"))
        let source = AVURLAsset(url: fixture)
        let sourceTrack = try #require(try await source.loadTracks(withMediaType: .video).first)
        let sourceFormat = try #require(try await sourceTrack.load(.formatDescriptions).first)
        let originalColor = try #require(CMFormatDescriptionGetExtensions(sourceFormat)) as NSDictionary
        #expect(originalColor[kCMFormatDescriptionExtension_TransferFunction] as? String == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        let prepared = try await VideoPreparation.prepare(inputURL: fixture)
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        let asset = AVURLAsset(url: prepared.url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let color = try #require(CMFormatDescriptionGetExtensions(format)) as NSDictionary
        #expect(color[kCMFormatDescriptionExtension_TransferFunction] as? String == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(color[kCMFormatDescriptionExtension_ColorPrimaries] as? String == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        try await VideoPreparation.verifyPrivacy(of: prepared.url)
        #expect(try Data(contentsOf: prepared.url).range(of: Data("PrivateHDRSentinel".utf8)) == nil)
        #expect(await getVideoFirstFrame(asset: asset) != nil)
    }

    @Test func largeSourceIsActuallyDownscaledAndDecodable() async throws {
        let source = try await makeVideo(size: CGSize(width: 2048, height: 1152), frameCount: 3)
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try await VideoPreparation.prepare(inputURL: source)
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        #expect(prepared.dimensions == CGSize(width: 1920, height: 1080))
        let frame = try #require(await getVideoFirstFrame(asset: AVURLAsset(url: prepared.url)))
        #expect(frame.size.width > 0 && frame.size.height > 0)
        let track = try #require(try await AVURLAsset(url: prepared.url).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1920, height: 1080))
    }

    @Test @MainActor func nip96CompletionUsesServerMetadataAndRefusesErrorResponses() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let fallback = PreparedPostVideoMedia(key: "video", fileURL: URL(fileURLWithPath: "/unused"), contentType: "video/mp4",
                                             hash: "local-hash", dim: "1920x1080", blurhash: nil, videoID: nil)
        let success = Data(#"{"status":"success","nip94_event":{"tags":[["url","https://example.com/processed.mp4"],["x","processed-hash"],["dim","1280x720"]]}}"#.utf8)
        let imeta = try await finishVideoNip96(data: success, session: session, baseURL: URL(string: "https://example.com/api")!, fallback: fallback) { _ in
            Issue.record("A completed upload should not poll")
        }
        #expect(imeta.dim == "1280x720")
        #expect(imeta.hash == "processed-hash")
        for json in [#"{"status":"error"}"#, #"{"status":"success"}"#] {
            do {
                _ = try await finishVideoNip96(data: Data(json.utf8), session: session, baseURL: URL(string: "https://example.com/api")!, fallback: fallback) { _ in }
                Issue.record("An incomplete server response must not become a published attachment")
            } catch PostVideoUploadError.invalidResponse { }
        }
    }

    @Test @MainActor func nip96PollingKeepsInitialProcessingURLWhenLaterRepliesOmitIt() async throws {
        VideoProcessingProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoProcessingProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let initial = Data(#"{"status":"processing","processing_url":"/status","percentage":20}"#.utf8)
        let fallback = PreparedPostVideoMedia(key: "video", fileURL: URL(fileURLWithPath: "/unused"), contentType: "video/mp4",
                                             hash: "local", dim: "1920x1080", blurhash: nil, videoID: nil)
        var states: [ComposerMediaUploadState] = []
        let imeta = try await finishVideoNip96(data: initial, session: session, baseURL: URL(string: "https://processing.example/api")!, fallback: fallback) { states.append($0) }
        #expect(imeta.url == "https://processing.example/video.mp4")
        #expect(states == [.processing(percentage: 20), .processing(percentage: 70)])
    }

    @Test func recordedMovieIsKeptLocallyThenSanitizedBeforeUpload() async throws {
        let fixture = try #require(Bundle(for: VideoPreparationTestBundle.self).url(forResource: "hlg-10bit", withExtension: "mov"))
        let copy = try await RecordedVideoFile.copy(from: fixture)
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(copy != fixture)
        #expect(copy.pathExtension == "mov")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: fixture))
        let prepared = try await VideoPreparation.prepare(inputURL: copy)
        defer { try? FileManager.default.removeItem(at: prepared.url) }
        #expect(prepared.url != copy)
        try await VideoPreparation.verifyPrivacy(of: prepared.url)
        #expect(try Data(contentsOf: prepared.url).range(of: Data("PrivateHDRSentinel".utf8)) == nil)
    }

    private func makeVideo(rotated: Bool = false, size: CGSize = CGSize(width: 64, height: 32), frameCount: Int = 60) async throws -> URL {
        let url = TemporaryMediaFiles.shared.makeURL(extension: "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [
            metadata(.quickTimeMetadataAuthor, "PrivateAuthorSentinel"),
            metadata(.quickTimeMetadataModel, "PrivateDeviceSentinel"),
            metadata(.quickTimeMetadataLocationISO6709, "+52.3702+004.8952/"),
            metadata(.quickTimeMetadataCreationDate, "2020-01-02T03:04:05Z")
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        input.metadata = [metadata(.quickTimeMetadataDescription, "PrivateAuthorSentinel")]
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 32, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        guard writer.startWriting() else { throw VideoPreparationError.cannotEncode }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixel = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), 120, CVPixelBufferGetDataSize(pixel))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw VideoPreparationError.cannotEncode
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoPreparationError.cannotEncode }
        return url
    }

    private func metadata(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }
}

private final class VideoPreparationTestBundle: NSObject {}


private final class VideoProcessingProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "processing.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        let count = Self.count
        Self.lock.unlock()
        let json = count == 1
            ? #"{"status":"processing","percentage":70}"#
            : #"{"status":"success","nip94_event":{"tags":[["url","https://processing.example/video.mp4"]]}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
