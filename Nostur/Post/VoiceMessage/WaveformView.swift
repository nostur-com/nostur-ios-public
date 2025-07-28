//
//  WaveformView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/07/2025.
//

import SwiftUI
import AVFoundation

struct WaveformView: View {
    @Environment(\.theme) private var theme
    var samples: [Int]
    @Binding var progress: Double
    var onScrub: ((Double) -> Void)? = nil
    var duration: TimeInterval = 0
    var isPlaying: Bool = false
    
    @State var isScrubbing: Bool = false
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        GeometryReader { geo in
            HStack {
                ZStack {
                    WaveformShape(samples: samples)
                        .fill(theme.accent.opacity(0.3))
                    WaveformShape(samples: samples)
                        .fill(theme.accent)
                        .clipShape(
                            Rectangle()
                                .size(width: geo.size.width * progress, height: geo.size.height)
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let newProgress = value.location.x / geo.size.width
                            let clampedProgress = min(max(newProgress, 0), 1)
                            progress = clampedProgress
                            onScrub?(clampedProgress)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                        }
                )
                
                Text(isPlaying ? formatTime(duration * progress) : formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Cache for audio samples to avoid reprocessing
private nonisolated(unsafe) var audioSamplesCache: [URL: [Int]] = [:]

func loadAudioSamples(from url: URL, sampleCount: Int = 100) async throws -> [Int] {
    // Check cache first
    if let cached = audioSamplesCache[url] {
        return cached
    }
    
    // Try AVAudioFile first for supported formats
    do {
        let audioFile = try AVAudioFile(forReading: url)
        return try loadSamplesFromAudioFile(audioFile, sampleCount: sampleCount, url: url)
    } catch {
        L.a0.error("loadAudioSamples AVAudioFile failed, trying AVAudioEngine instead, error: \(error)")
        // If AVAudioFile fails (e.g., for Opus), try AVAudioEngine approach
        return try await loadSamplesWithAudioEngine(from: url, sampleCount: sampleCount)
    }
}

private func loadSamplesFromAudioFile(_ audioFile: AVAudioFile, sampleCount: Int, url: URL) throws -> [Int] {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: audioFile.processingFormat.sampleRate,
                                   channels: audioFile.processingFormat.channelCount,
                                   interleaved: audioFile.processingFormat.isInterleaved) else {
        L.a0.error("loadSamplesFromAudioFile: Failed to create audio format")
        throw NSError(domain: "AudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
    }

    let frameCount = UInt32(audioFile.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        L.a0.error("loadSamplesFromAudioFile: Failed to create buffer")
        throw NSError(domain: "AudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
    }

    try audioFile.read(into: buffer)
    let samples = try processSamples(from: buffer, sampleCount: sampleCount)
    
    // Cache result
    audioSamplesCache[url] = samples
    return samples
}

private func loadSamplesWithAudioEngine(from url: URL, sampleCount: Int) async throws -> [Int] {
    let asset = AVURLAsset(url: url)
    
    // Get audio track
    guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
        L.a0.error("loadSamplesWithAudioEngine: No audio track found")
        throw NSError(domain: "AudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
    }
    
    // Use AVAssetReader directly to avoid timing offset from AVAssetExportSession
    let assetReader = try AVAssetReader(asset: asset)
    
    // Configure output settings for PCM format
    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    
    let assetReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    assetReader.add(assetReaderOutput)
    
    guard assetReader.startReading() else {
        L.a0.error("loadSamplesWithAudioEngine: Failed to start reading asset")
        throw NSError(domain: "AudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading asset"])
    }
    
    var audioSamples: [Float] = []
    
    while let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
        
        let length = CMBlockBufferGetDataLength(blockBuffer)
        let sampleCount = length / MemoryLayout<Float>.size
        var audioData = [Float](repeating: 0, count: sampleCount)
        
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &audioData)
        audioSamples.append(contentsOf: audioData)
    }
    
    // Process samples to match the required count
    let totalSamples = audioSamples.count
    let step = max(1, totalSamples / sampleCount)
    var processedSamples: [Float] = []
    processedSamples.reserveCapacity(sampleCount)
    var maxAmplitude: Float = 0
    
    for i in stride(from: 0, to: totalSamples, by: step) {
        let amplitude = abs(audioSamples[i])
        processedSamples.append(amplitude)
        maxAmplitude = max(maxAmplitude, amplitude)
    }
    
    // Enhanced normalization for better visibility - convert to Int (0-100)
    let normalizedSamples = processedSamples.map { sample in
        guard maxAmplitude > 0 else { return 0 }
        // Normalize to 0-1 range first
        let normalized = sample / maxAmplitude
        // Apply logarithmic scaling for better dynamic range
        let logScaled = log10(normalized * 9 + 1) // Maps 0-1 to 0-1 with log curve
        // Apply aggressive scaling with minimum threshold
        let scaled = max(logScaled * 3.0, normalized * 0.3) // 3x scaling with 0.3x minimum
        return min(Int(scaled * 100), 100) // Convert to Int 0-100 range
    }
    
    // Cache result
    audioSamplesCache[url] = normalizedSamples
    return normalizedSamples
}

private func processSamples(from audioFile: AVAudioFile, sampleCount: Int) throws -> [Int] {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: audioFile.processingFormat.sampleRate,
                                   channels: audioFile.processingFormat.channelCount,
                                   interleaved: audioFile.processingFormat.isInterleaved) else {
        L.a0.error("processSamples(AVAudioFile): Failed to create audio format")
        throw NSError(domain: "AudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
    }

    let frameCount = UInt32(audioFile.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        L.a0.error("processSamples(AVAudioFile): Failed to create buffer")
        throw NSError(domain: "AudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
    }

    try audioFile.read(into: buffer)
    return try processSamples(from: buffer, sampleCount: sampleCount)
}

private func processSamples(from buffer: AVAudioPCMBuffer, sampleCount: Int) throws -> [Int] {
    guard let floatChannelData = buffer.floatChannelData else {
        L.a0.error("processSamples(AVAudioPCMBuffer): Failed to get float channel data")
        throw NSError(domain: "AudioError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get float channel data"])
    }

    let channelCount = Int(buffer.format.channelCount)
    let totalSamples = Int(buffer.frameLength)
    let step = max(1, totalSamples / sampleCount)
    
    var samples: [Float] = []
    samples.reserveCapacity(sampleCount)
    var maxAmplitude: Float = 0

    if channelCount == 1 {
        let sampleData = UnsafeBufferPointer(start: floatChannelData[0], count: totalSamples)
        for i in stride(from: 0, to: totalSamples, by: step) {
            let amplitude = abs(sampleData[i])
            samples.append(amplitude)
            maxAmplitude = max(maxAmplitude, amplitude)
        }
    } else {
        let leftChannel = UnsafeBufferPointer(start: floatChannelData[0], count: totalSamples)
        let rightChannel = UnsafeBufferPointer(start: floatChannelData[1], count: totalSamples)
        for i in stride(from: 0, to: totalSamples, by: step) {
            let amplitude = abs((leftChannel[i] + rightChannel[i]) / 2)
            samples.append(amplitude)
            maxAmplitude = max(maxAmplitude, amplitude)
        }
    }

    if maxAmplitude == 0 {
        L.a0.error("processSamples(AVAudioPCMBuffer): No valid amplitude data")
        throw NSError(domain: "AudioError", code: 4, userInfo: [NSLocalizedDescriptionKey: "No valid amplitude data"])
    }
    
    let normalizedSamples = samples.map { sample in
        // Normalize to 0-1 range first
        let normalized = sample / maxAmplitude
        // Apply logarithmic scaling for better dynamic range
        let logScaled = log10(normalized * 9 + 1) // Maps 0-1 to 0-1 with log curve
        // Apply aggressive scaling with minimum threshold
        let scaled = max(logScaled * 3.0, normalized * 0.3) // 3x scaling with 0.3x minimum
        return min(Int(scaled * 100), 100) // Convert to Int 0-100 range
    }
    
    return normalizedSamples
}

// Async version for better UI responsiveness
func loadAudioSamplesAsync(from url: URL, sampleCount: Int = 100) async throws -> [Int] {
    return try await loadAudioSamples(from: url, sampleCount: sampleCount)
}

func loadAudioSamples(from data: Data, sampleCount: Int = 100) throws -> [Int] {
    // Assume data is raw PCM audio (float32 format) since AVAudioFile requires file URLs
    // Create an AVAudioFormat for raw PCM data
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
        L.a0.error("loadAudioSamples: Format creation failed")
        throw NSError(domain: "AudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
    }

    // Calculate frame count based on data size (assuming float32 PCM, 4 bytes per sample)
    let bytesPerSample = 4 // Float32 is 4 bytes
    let channelCount = Int(format.channelCount)
    let totalSamples = data.count / bytesPerSample
    let frameCount = UInt32(totalSamples)

    guard frameCount > 0 else {
        L.a0.error("loadAudioSamples: No valid audio data")
        throw NSError(domain: "AudioError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty audio data"])
    }

    // Create PCM buffer
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        L.a0.error("loadAudioSamples: Buffer creation failed")
        throw NSError(domain: "AudioError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
    }

    // Copy data into buffer
    data.withUnsafeBytes { rawBuffer in
        guard let floatChannelData = buffer.floatChannelData else { return }
        memcpy(floatChannelData[0], rawBuffer.baseAddress, data.count)
        buffer.frameLength = frameCount
    }

    L.a0.debug("loadAudioSamples: Successfully loaded \(buffer.frameLength) frames")

    guard let floatChannelData = buffer.floatChannelData else {
        L.a0.error("loadAudioSamples: Float channel data unavailable")
        throw NSError(domain: "AudioError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get float channel data"])
    }

    // Process samples (similar to original function)
    var downsampled: [Float] = []
    let step = max(1, totalSamples / sampleCount)
    
    if channelCount == 1 {
        let sampleData = UnsafeBufferPointer(start: floatChannelData[0], count: totalSamples)
        downsampled = stride(from: 0, to: totalSamples, by: step).map { index in
            abs(sampleData[index])
        }
    } else {
        let leftChannel = UnsafeBufferPointer(start: floatChannelData[0], count: totalSamples)
        let rightChannel = UnsafeBufferPointer(start: floatChannelData[1], count: totalSamples)
        downsampled = stride(from: 0, to: totalSamples, by: step).map { index in
            abs((leftChannel[index] + rightChannel[index]) / 2)
        }
    }

    let maxAmplitude = downsampled.max() ?? 1.0
    if maxAmplitude == 0 {
        L.a0.error("loadAudioSamples: Max amplitude is zero")
        throw NSError(domain: "AudioError", code: 5, userInfo: [NSLocalizedDescriptionKey: "No valid amplitude data (all samples zero)"])
    }
    let normalizedSamples = downsampled.map { 
        let normalized = ($0 / maxAmplitude) * 1.5
        return Int(round(normalized * 100))
    }
    
    L.a0.debug("loadAudioSamples: Processed \(normalizedSamples.count) samples, max amplitude: \(maxAmplitude)")
    L.a0.debug("loadAudioSamples: Samples: \(normalizedSamples.suffix(20))")
    return normalizedSamples
}

// Waveform shape with iMessage-like bars
struct WaveformShape: Shape {
    var samples: [Int]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let sampleCount = samples.count
        
        guard sampleCount > 0 else {
            L.a0.debug("WaveformShape: No samples to render")
            return path
        }
        
        let barWidth: CGFloat = 4
        let spacing: CGFloat = 2
        let totalBarWidth = barWidth + spacing
        let maxBars = max(Int(width / totalBarWidth), 20)
        let step = max(1, sampleCount / maxBars)
        let maxBarExtent: CGFloat = height / 2
        
        for i in 0..<min(sampleCount, maxBars) {
            let sampleIndex = i * step
            let amplitude = CGFloat(samples[sampleIndex]) / 100.0 // Convert from 0-100 to 0.0-1.0
            let barExtent = amplitude * maxBarExtent
            let x = CGFloat(i) * totalBarWidth
            let y = height / 2
            
            path.addRoundedRect(
                in: CGRect(x: x, y: y - barExtent, width: barWidth, height: barExtent * 2),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
        }
        
        return path
    }
}


@available(iOS 17.0, *)
#Preview("WaveformView") {
    @Previewable @State var fileURL: URL = URL(string: "/Users/fabian/Library/Developer/Xcode/UserData/Previews/Simulator Devices/644216E9-8CEF-43E9-8711-2ECED8397AC9/data/Containers/Data/Application/7EE55354-E822-4F12-860E-A99119F2CE76/tmp/CFNetworkDownload_fWdRdS.tmp")!
    @Previewable @State var dummyProgress: Double = 0.0
    WaveformView(samples: [], progress: $dummyProgress, onScrub: { _ in }, duration: 125, isPlaying: true)
        .frame(height: 100)
        .task {
//            dummyURL = URL(string: "http://localhost:3000/f3290797cd055bc7417a4736e09b509abc9ba08d3558f1c48d9d348711512ec0.m4a")
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                dummyProgress += 0.01
                if dummyProgress > 1.0 { dummyProgress = 0.0 }
            }
        }
}



