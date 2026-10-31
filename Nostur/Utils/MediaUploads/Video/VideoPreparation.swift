import AVFoundation
import CryptoKit
import Foundation

/// All choices remove source metadata. Higher quality changes dimensions only.
enum VideoUploadQuality: String, CaseIterable, Sendable {
    case automatic, higher, smaller

    func outputSize(for size: CGSize, shortVideo: Bool) -> CGSize {
        let longEdge: CGFloat = shortVideo || self == .smaller ? 1280 : (self == .higher ? 3840 : 1920)
        let shortEdge: CGFloat = shortVideo || self == .smaller ? 720 : (self == .higher ? 2160 : 1080)
        let scale = min(1, min(longEdge / max(size.width, size.height), shortEdge / min(size.width, size.height)))
        return CGSize(width: max(2, floor(size.width * scale / 2) * 2),
                      height: max(2, floor(size.height * scale / 2) * 2))
    }

    func outputFrameRate(_ source: Float) -> Float {
        let fps = source.isFinite && source > 0 ? source : 30
        return min(fps, self == .smaller ? 30 : 60)
    }

    func bitRate(size: CGSize, fps: Float, sourceBitRate: Float) -> Int {
        let target = min(max(Double(size.width * size.height) * min(max(Double(fps), 30), 60) * 0.10, 2_500_000), 16_000_000)
        // Do not inflate a low-bitrate source to the usual quality floor.
        let budget = sourceBitRate > 0 ? min(target, Double(sourceBitRate)) : target
        return Int(self == .smaller ? budget * 0.60 : budget)
    }
}

struct PreparedVideo: Sendable {
    let url: URL
    let dimensions: CGSize
    let duration: Double
    let byteCount: Int64
    let sha256: String
    let quality: VideoUploadQuality
    let shortVideo: Bool
}

enum VideoPreparationError: LocalizedError {
    case invalidVideo, cannotEncode, unsafeMetadata

    var errorDescription: String? {
        switch self {
        case .invalidVideo: return String(localized: "This video could not be read. Choose another video or try again.")
        case .cannotEncode: return String(localized: "Could not prepare this video. Your attachment has been kept. Please try again.")
        case .unsafeMetadata: return String(localized: "Could not remove the video's metadata. The video has not been uploaded.")
        }
    }
}

/// Fresh A/V tracks and decoded samples are intentional: no original-file or
/// compressed-sample fallback can forward source location, device or author data.
enum VideoPreparation {
    static func prepare(inputURL: URL, quality: VideoUploadQuality = .automatic,
                        shortVideo: Bool = false, start: Double = 0, end: Double? = nil,
                        muted: Bool = false,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> PreparedVideo {
        try Task.checkCancellation()
        let source = AVURLAsset(url: inputURL)
        guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first else {
            throw VideoPreparationError.invalidVideo
        }
        let sourceDuration = try await source.load(.duration).seconds
        let finalEnd = min(end ?? sourceDuration, sourceDuration)
        guard start.isFinite, finalEnd.isFinite, start >= 0, finalEnd > start else { throw VideoPreparationError.invalidVideo }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: finalEnd - start, preferredTimescale: 600))
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard sourceRect.width.isFinite, sourceRect.height.isFinite,
              sourceRect.width > 0, sourceRect.height > 0 else { throw VideoPreparationError.invalidVideo }
        let size = quality.outputSize(for: sourceRect.size, shortVideo: shortVideo)
        let nominalFPS = try await sourceVideo.load(.nominalFrameRate)
        let outputFPS = quality.outputFrameRate(nominalFPS)
        let formats = try await sourceVideo.load(.formatDescriptions)
        let isH264 = formats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 } ?? false
        // HEVC source bitrates are not an equivalent quality budget for H.264.
        let estimatedBitRate = try await sourceVideo.load(.estimatedDataRate)
        let sourceBitRate: Float = isH264 ? estimatedBitRate : 0

        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoPreparationError.cannotEncode
        }
        try video.insertTimeRange(range, of: sourceVideo, at: .zero)
        if !muted, let sourceAudio = try await source.loadTracks(withMediaType: .audio).first {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoPreparationError.cannotEncode
            }
            let audioRange = try await sourceAudio.load(.timeRange).intersection(range)
            if audioRange.duration.seconds > 0 {
                try audio.insertTimeRange(audioRange, of: sourceAudio, at: audioRange.start - range.start)
            }
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1000, timescale: Int32((outputFPS * 1000).rounded()))
        // The built-in compositor performs HDR -> SDR conversion before encoding.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY))
            .concatenating(CGAffineTransform(scaleX: size.width / sourceRect.width, y: size.height / sourceRect.height))
        layer.setTransform(normalized, at: .zero)
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        let outputURL = TemporaryMediaFiles.shared.makeURL(extension: "mp4")
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: outputURL) } }
        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.metadata = []
        writer.shouldOptimizeForNetworkUse = true
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [video], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        let color: [String: Any] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: color,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitRate(size: size, fps: outputFPS, sourceBitRate: sourceBitRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Int(outputFPS.rounded()), AVVideoMaxKeyFrameIntervalDurationKey: 2
            ]
        ])
        videoInput.metadata = []
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw VideoPreparationError.cannotEncode }
        reader.add(videoOutput)
        writer.add(videoInput)
        var streams: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
        if let audio = composition.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 128_000,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2
            ])
            input.metadata = []
            guard reader.canAdd(output), writer.canAdd(input) else { throw VideoPreparationError.cannotEncode }
            reader.add(output)
            writer.add(input)
            streams.append((output, input))
        }
        let session = VideoEncodingSession(reader: reader, writer: writer, streams: streams,
                                           duration: range.duration.seconds, progress: progress)
        try await session.run()
        try Task.checkCancellation()
        try await verifyPrivacy(of: outputURL)
        let hash = try hashFile(outputURL)
        let bytes = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw VideoPreparationError.cannotEncode }
        completed = true
        return PreparedVideo(url: outputURL, dimensions: size, duration: range.duration.seconds,
                             byteCount: Int64(bytes), sha256: hash, quality: quality, shortVideo: shortVideo)
    }

    static func verifyPrivacy(of url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.metadata).isEmpty else { throw VideoPreparationError.unsafeMetadata }
        for format in try await asset.load(.availableMetadataFormats) {
            guard try await asset.loadMetadata(for: format).isEmpty else { throw VideoPreparationError.unsafeMetadata }
        }
        let tracks = try await asset.load(.tracks)
        for track in tracks {
            guard track.mediaType == .video || track.mediaType == .audio,
                  try await track.load(.metadata).isEmpty else { throw VideoPreparationError.unsafeMetadata }
        }
    }

    static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// All AVFoundation mutation and continuation ownership is confined to this queue.
/// Cancellation also completes when writer backpressure has paused sample callbacks.
private final class VideoEncodingSession: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let streams: [(AVAssetReaderOutput, AVAssetWriterInput)]
    let duration: Double
    let progress: @Sendable (Double) -> Void
    private let queue = DispatchQueue(label: "com.nostur.video-preparation")
    private var continuation: CheckedContinuation<Void, Error>?
    private let cancellation = VideoEncodingCancellation()
    private var finished = false
    private var ended = Set<Int>()
    private var lastProgress = -1

    init(reader: AVAssetReader, writer: AVAssetWriter, streams: [(AVAssetReaderOutput, AVAssetWriterInput)],
         duration: Double, progress: @escaping @Sendable (Double) -> Void) {
        self.reader = reader; self.writer = writer; self.streams = streams
        self.duration = duration; self.progress = progress
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    if self.cancellation.isCancelled { self.complete(.failure(CancellationError())); return }
                    guard self.writer.startWriting(), self.reader.startReading() else {
                        self.complete(.failure(VideoPreparationError.cannotEncode)); return
                    }
                    self.writer.startSession(atSourceTime: .zero)
                    for index in self.streams.indices {
                        self.streams[index].1.requestMediaDataWhenReady(on: self.queue) { self.pump(index) }
                    }
                }
            }
        } onCancel: {
            self.cancellation.cancel()
            self.queue.async {
                if self.continuation != nil { self.complete(.failure(CancellationError())) }
            }
        }
    }

    private func pump(_ index: Int) {
        guard !finished, !ended.contains(index) else { return }
        let (output, input) = streams[index]
        while input.isReadyForMoreMediaData {
            if cancellation.isCancelled { complete(.failure(CancellationError())); return }
            guard let sample = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                ended.insert(index)
                if ended.count == streams.count {
                    guard reader.status == .completed else { complete(.failure(VideoPreparationError.cannotEncode)); return }
                    writer.finishWriting {
                        self.queue.async {
                            self.complete(self.writer.status == .completed ? .success(()) : .failure(VideoPreparationError.cannotEncode))
                        }
                    }
                }
                return
            }
            guard input.append(sample) else { complete(.failure(VideoPreparationError.cannotEncode)); return }
            if index == 0 {
                let percent = min(99, max(0, Int(sample.presentationTimeStamp.seconds / duration * 100)))
                if percent != lastProgress { lastProgress = percent; progress(Double(percent) / 100) }
            }
        }
    }

    private func complete(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        if case .failure = result {
            reader.cancelReading()
            writer.cancelWriting()
        } else { progress(1) }
        continuation?.resume(with: result)
        continuation = nil
    }
}


/// Only a Boolean is locked; encoding, callbacks and I/O never run under it.
private final class VideoEncodingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
