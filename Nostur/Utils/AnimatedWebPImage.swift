//
//  AnimatedWebPImage.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2025.
//

import SwiftUI
import ImageIO
import Combine

// Returns true if data is an animated WebP (RIFF/WEBP header + more than one frame via ImageIO)
func isAnimatedWebPData(_ data: Data) -> Bool {
    guard data.count >= 20 else { return false }

    // WebP container signature: RIFF....WEBP
    guard data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,  // RIFF
          data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50  // WEBP
    else { return false }

    // Walk RIFF chunks and detect animation chunks without full image decoding.
    var offset = 12
    while offset + 8 <= data.count {
        let chunkId0 = data[offset]
        let chunkId1 = data[offset + 1]
        let chunkId2 = data[offset + 2]
        let chunkId3 = data[offset + 3]

        // "ANIM" or "ANMF"
        let isAnimChunk = chunkId0 == 0x41 && chunkId1 == 0x4E && chunkId2 == 0x49 && chunkId3 == 0x4D
        let isAnimFrameChunk = chunkId0 == 0x41 && chunkId1 == 0x4E && chunkId2 == 0x4D && chunkId3 == 0x46
        if isAnimChunk || isAnimFrameChunk {
            return true
        }

        let chunkSize = Int(data[offset + 4])
            | (Int(data[offset + 5]) << 8)
            | (Int(data[offset + 6]) << 16)
            | (Int(data[offset + 7]) << 24)
        if chunkSize < 0 { return false }

        // Chunks are padded to even sizes.
        let paddedChunkSize = chunkSize + (chunkSize % 2)
        let nextOffset = offset + 8 + paddedChunkSize
        if nextOffset <= offset || nextOffset > data.count { break }
        offset = nextOffset
    }

    return false
}

// Renders animated WebP data using ImageIO frame extraction, mirroring GIFImage.
public struct AnimatedWebPImage: View {
    private let data: Data
    @Binding var isPlaying: Bool
    @State private var replayToken = 0
    @State private var hasReachedLoopLimit = false
    @State private var hasLoadedDuration = false
    @State private var animationDuration: TimeInterval = 0.1
    @State private var stopTask: Task<Void, Never>?

    public init(data: Data, isPlaying: Binding<Bool>) {
        self.data = data
        _isPlaying = isPlaying
    }

    public var body: some View {
        _AnimatedWebPImage(data: data, isPlaying: .constant(isPlaying && !hasReachedLoopLimit), replayToken: replayToken)
            .contentShape(Rectangle())
            .onAppear {
                prepareAnimationDuration()
                scheduleLoopLimitStop()
            }
            .onChange(of: isPlaying) { newValue in
                if newValue {
                    hasReachedLoopLimit = false
                    prepareAnimationDuration()
                    scheduleLoopLimitStop()
                }
                else {
                    stopTask?.cancel()
                    stopTask = nil
                }
            }
            .onDisappear {
                stopTask?.cancel()
                stopTask = nil
            }
            .modifier(GIFReplayModifier(isStopped: hasReachedLoopLimit) {
                restartPlayback()
            })
    }
    
    private func restartPlayback() {
        hasReachedLoopLimit = false
        replayToken += 1
        scheduleLoopLimitStop()
    }
    
    private func scheduleLoopLimitStop() {
        stopTask?.cancel()
        guard isPlaying else { return }
        
        let duration = animationDuration * 5.0
        stopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            hasReachedLoopLimit = true
        }
    }

    private func prepareAnimationDuration() {
        guard !hasLoadedDuration else { return }

        let data = self.data
        DispatchQueue.global(qos: .utility).async {
            let duration = animatedWebPDuration(data)
            DispatchQueue.main.async {
                hasLoadedDuration = true
                animationDuration = duration
                if isPlaying && !hasReachedLoopLimit {
                    scheduleLoopLimitStop()
                }
            }
        }
    }
}

private struct _AnimatedWebPImage: UIViewRepresentable {
    let data: Data
    @Binding var isPlaying: Bool
    let replayToken: Int

    func makeUIView(context: Context) -> WebPAnimatedImageView {
        let imageView = WebPAnimatedImageView()
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.isUserInteractionEnabled = false

        receiveNotification(.scenePhaseBackground)
            .receive(on: RunLoop.main)
            .sink { _ in
                imageView.stopAnimatingWebP()
            }
            .store(in: &context.coordinator.subscriptions)
        receiveNotification(.scenePhaseActive)
            .receive(on: RunLoop.main)
            .sink { _ in
                guard isPlaying else { return }
                imageView.startAnimatingWebP()
            }
            .store(in: &context.coordinator.subscriptions)

        imageView.prepareForAnimation(withWebPData: data)
        if isPlaying {
            imageView.startAnimatingWebP()
        }
        return imageView
    }

    func updateUIView(_ imageView: WebPAnimatedImageView, context: Context) {
        if replayToken != context.coordinator.lastReplayToken {
            context.coordinator.lastReplayToken = replayToken
            guard isPlaying else { return }
            imageView.restartWebPAnimation()
            return
        }

        if isPlaying {
            imageView.startAnimatingWebP()
        } else {
            imageView.stopAnimatingWebP()
        }
    }

    static func dismantleUIView(_ imageView: WebPAnimatedImageView, coordinator: Coordinator) {
        imageView.prepareForReuse()
        coordinator.subscriptions.removeAll()
    }

    class Coordinator: NSObject {
        var lastReplayToken = 0
        var subscriptions = Set<AnyCancellable>()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

private final class WebPAnimatedImageView: UIImageView {
    private let decodeQueue = DispatchQueue(label: "Nostur.WebPAnimatedImage.decode", qos: .utility)
    private let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    private let maxRenderableFrames = 120
    private let maxBufferedFrames = 12
    private let minPlaybackFrameDuration = 1.0 / 30.0

    private var source: CGImageSource?
    private var playbackFrameIndices: [Int] = []
    private var playbackDurations: [Double] = []
    private var frameCount = 0
    private var currentPlaybackIndex = 0
    private var currentFrameElapsed: TimeInterval = 0
    private var playbackGeneration = 0
    private var displayLink: CADisplayLink?
    private var bufferedFrames: [Int: UIImage] = [:]
    private var pendingDecodes = Set<Int>()
    private var isPlayingRequested = false
    private var isPrepared = false
    private var decodeMaxPixelSize: CGFloat = UIScreen.main.bounds.width * UIScreen.main.scale

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let width = max(bounds.width, 1.0)
        let height = max(bounds.height, 1.0)
        let maxDimension = max(width, height) * scale
        decodeMaxPixelSize = max(maxDimension, UIScreen.main.bounds.width * UIScreen.main.scale)
    }

    func prepareForAnimation(withWebPData data: Data) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let generation = self.nextGeneration()
            self.isPrepared = false
            self.source = nil
            self.playbackFrameIndices.removeAll(keepingCapacity: false)
            self.playbackDurations.removeAll(keepingCapacity: false)
            self.frameCount = 0
            self.currentPlaybackIndex = 0
            self.currentFrameElapsed = 0
            self.bufferedFrames.removeAll(keepingCapacity: false)
            self.pendingDecodes.removeAll(keepingCapacity: false)

            guard let source = CGImageSourceCreateWithData(data as CFData, self.sourceOptions as CFDictionary) else { return }
            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 0 else { return }

            var frameDurations: [Double] = []
            frameDurations.reserveCapacity(frameCount)
            for index in 0..<frameCount {
                frameDurations.append(frameDuration(source: source, index: index))
            }

            var playbackIndices: [Int] = []
            var playbackDurations: [Double] = []
            if frameCount <= self.maxRenderableFrames {
                playbackIndices = Array(0..<frameCount)
                playbackDurations = frameDurations
            } else {
                let stride = max(1, frameCount / self.maxRenderableFrames)
                var index = 0
                while index < frameCount {
                    let nextIndex = min(index + stride, frameCount)
                    let duration = frameDurations[index..<nextIndex].reduce(0, +)
                    playbackIndices.append(index)
                    playbackDurations.append(duration)
                    index = nextIndex
                }
                if playbackIndices.last != frameCount - 1 {
                    playbackIndices.append(frameCount - 1)
                    playbackDurations.append(frameDurations.last ?? 0.1)
                }
            }

            guard let firstFrame = self.decodeFrameImage(source: source, frameIndex: 0) else { return }

            guard generation == self.playbackGeneration else { return }
            self.source = source
            self.frameCount = frameCount
            self.playbackFrameIndices = playbackIndices
            self.playbackDurations = playbackDurations
            self.currentPlaybackIndex = 0
            self.isPrepared = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let image = UIImage(cgImage: firstFrame)
                self.image = image
                self.bufferedFrames[0] = image
                self.prefetchFramesAroundCurrentIndex(generation: generation)
            }

            if self.isPlayingRequested {
                DispatchQueue.main.async { [weak self] in
                    self?.startDisplayLink(generation: generation)
                }
            }
        }
    }

    func startAnimatingWebP() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPlayingRequested = true
            guard self.isPrepared else { return }
            let generation = self.nextGeneration()
            self.currentFrameElapsed = 0
            self.startDisplayLink(generation: generation)
        }
    }

    func stopAnimatingWebP() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPlayingRequested = false
            self.stopDisplayLink()
        }
    }

    func restartWebPAnimation() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentPlaybackIndex = 0
            self.isPlayingRequested = true
            guard self.isPrepared else { return }
            let generation = self.nextGeneration()
            self.currentFrameElapsed = 0
            self.showFrameIfBuffered(playbackIndex: 0)
            self.prefetchFramesAroundCurrentIndex(generation: generation)
            self.startDisplayLink(generation: generation)
        }
    }

    func prepareForReuse() {
        stopAnimatingWebP()
        decodeQueue.async { [weak self] in
            guard let self else { return }
            self.isPrepared = false
            self.source = nil
            self.playbackFrameIndices.removeAll(keepingCapacity: false)
            self.playbackDurations.removeAll(keepingCapacity: false)
            self.frameCount = 0
            self.currentPlaybackIndex = 0
            self.currentFrameElapsed = 0
        }
        DispatchQueue.main.async { [weak self] in
            self?.bufferedFrames.removeAll(keepingCapacity: false)
            self?.pendingDecodes.removeAll(keepingCapacity: false)
            self?.image = nil
        }
    }

    private func nextGeneration() -> Int {
        playbackGeneration += 1
        return playbackGeneration
    }

    private func startDisplayLink(generation: Int) {
        stopDisplayLink()
        guard generation == playbackGeneration else { return }
        guard isPrepared, isPlayingRequested else { return }
        guard !playbackFrameIndices.isEmpty else { return }

        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 60, preferred: 30)
        displayLink.add(to: .main, forMode: .default)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        guard isPrepared, isPlayingRequested else {
            stopDisplayLink()
            return
        }
        guard !playbackFrameIndices.isEmpty else { return }

        let currentDuration = playbackDurations.indices.contains(currentPlaybackIndex)
            ? max(playbackDurations[currentPlaybackIndex], minPlaybackFrameDuration)
            : 0.1
        currentFrameElapsed += link.duration
        if currentFrameElapsed < currentDuration { return }
        currentFrameElapsed = 0

        currentPlaybackIndex = (currentPlaybackIndex + 1) % playbackFrameIndices.count
        showFrameIfBuffered(playbackIndex: currentPlaybackIndex)
        prefetchFramesAroundCurrentIndex(generation: playbackGeneration)
    }

    private func showFrameIfBuffered(playbackIndex: Int) {
        if let frame = bufferedFrames[playbackIndex] {
            image = frame
        }
        else {
            decodeFrame(playbackIndex: playbackIndex, generation: playbackGeneration)
        }
    }

    private func prefetchFramesAroundCurrentIndex(generation: Int) {
        guard generation == playbackGeneration else { return }
        guard isPrepared else { return }
        guard !playbackFrameIndices.isEmpty else { return }

        var keepKeys = Set<Int>()
        for offset in 0..<maxBufferedFrames {
            let playbackIndex = (currentPlaybackIndex + offset) % playbackFrameIndices.count
            keepKeys.insert(playbackIndex)
            if bufferedFrames[playbackIndex] == nil {
                decodeFrame(playbackIndex: playbackIndex, generation: generation)
            }
        }
        bufferedFrames = bufferedFrames.filter { keepKeys.contains($0.key) }
        pendingDecodes = pendingDecodes.intersection(keepKeys)
    }

    private func decodeFrame(playbackIndex: Int, generation: Int) {
        guard generation == playbackGeneration else { return }
        guard !pendingDecodes.contains(playbackIndex) else { return }
        guard let source else { return }
        guard !playbackFrameIndices.isEmpty else { return }

        pendingDecodes.insert(playbackIndex)
        let frameIndex = playbackFrameIndices[playbackIndex]

        decodeQueue.async { [weak self] in
            guard let self else { return }
            guard let cgImage = self.decodeFrameImage(source: source, frameIndex: frameIndex) else {
                DispatchQueue.main.async { [weak self] in
                    self?.pendingDecodes.remove(playbackIndex)
                }
                return
            }
            let frameImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.playbackGeneration else { return }
                self.pendingDecodes.remove(playbackIndex)
                self.bufferedFrames[playbackIndex] = frameImage
                if playbackIndex == self.currentPlaybackIndex {
                    self.image = frameImage
                }
            }
        }
    }

    private func decodeFrameImage(source: CGImageSource, frameIndex: Int) -> CGImage? {
        let maxPixelSize = Int(max(decodeMaxPixelSize, 1.0))
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, frameIndex, options as CFDictionary)
    }
}

private func frameDuration(source: CGImageSource, index: Int) -> Double {
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
        return 0.1
    }
    if let webpDict = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
        if let d = webpDict[kCGImagePropertyWebPUnclampedDelayTime] as? Double, d > 0 { return d }
        if let d = webpDict[kCGImagePropertyWebPDelayTime] as? Double, d > 0 { return d }
    }
    return 0.1
}

private func animatedWebPDuration(_ data: Data) -> TimeInterval {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0.1 }
    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else { return 0.1 }
    
    var totalDuration: TimeInterval = 0
    for index in 0..<frameCount {
        totalDuration += frameDuration(source: source, index: index)
    }
    return max(totalDuration, 0.1)
}
