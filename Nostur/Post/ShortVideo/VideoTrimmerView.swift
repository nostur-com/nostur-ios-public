//
//  VideoTrimmerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2026.
//

import SwiftUI
import AVFoundation
import AVKit

struct VideoTrimmerView: View {
    let sourceURL: URL
    let maxDuration: Double = 6.0
    var onTrimmed: (URL, Double) -> Void // (trimmedURL, duration)
    var onCancel: () -> Void
    
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 6.0
    @State private var currentTime: Double = 0
    @State private var thumbnails: [UIImage] = []
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var timeObserver: Any?
    @State private var isLoaded = false
    
    private var selectedDuration: Double {
        endTime - startTime
    }
    
    private var needsTrimming: Bool {
        duration > maxDuration
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Video preview
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxHeight: 400)
                    .overlay { ProgressView().tint(.white) }
                    .padding(.horizontal)
            }
            
            Spacer().frame(height: 20)
            
            // Duration info
            HStack {
                Text(formatTime(selectedDuration))
                    .font(.headline)
                    .monospacedDigit()
                
                Text("/ \(formatTime(maxDuration)) max")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            
            // Trim timeline
            if isLoaded {
                VStack(spacing: 4) {
                    Text("Drag handles to trim video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TrimTimelineView(
                        duration: duration,
                        startTime: $startTime,
                        endTime: $endTime,
                        maxDuration: maxDuration,
                        thumbnails: thumbnails
                    )
                    .frame(height: 60)
                    .padding(.horizontal)
                    
                    HStack {
                        Text(formatTime(startTime))
                        Spacer()
                        Text(formatTime(endTime))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 24)
                }
            }
            
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 20) {
                Button("Cancel") {
                    cleanup()
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button {
                    exportTrimmedVideo()
                } label: {
                    if isExporting {
                        ProgressView()
                            .frame(width: 100)
                    } else {
                        Text("Use Video")
                            .frame(width: 100)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || selectedDuration > maxDuration || selectedDuration < 0.5)
            }
            .padding(.bottom, 20)
        }
        .onAppear { loadVideo() }
        .onDisappear { cleanup() }
        .onChange(of: startTime) { _ in seekToStart() }
        .onChange(of: endTime) { _ in seekToStart() }
    }
    
    private func loadVideo() {
        let asset = AVURLAsset(url: sourceURL)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        Task {
            do {
                let durationCM = try await asset.load(.duration)
                let totalDuration = CMTimeGetSeconds(durationCM)
                
                await MainActor.run {
                    self.duration = totalDuration
                    self.endTime = min(totalDuration, maxDuration)
                    self.player = newPlayer
                    self.isLoaded = true
                    
                    // Add periodic time observer for looping within trim range
                    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
                    self.timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                        let current = CMTimeGetSeconds(time)
                        self.currentTime = current
                        if current >= self.endTime {
                            newPlayer.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600))
                        }
                    }
                    
                    newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                    newPlayer.play()
                }
                
                // Generate thumbnails
                await generateThumbnails(asset: asset, duration: totalDuration)
            } catch {
                await MainActor.run {
                    self.exportError = "Failed to load video"
                }
            }
        }
    }
    
    private func generateThumbnails(asset: AVAsset, duration: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 80, height: 80)
        
        let count = 10
        var times: [NSValue] = []
        for i in 0..<count {
            let time = CMTime(seconds: duration * Double(i) / Double(count), preferredTimescale: 600)
            times.append(NSValue(time: time))
        }
        
        await withCheckedContinuation { continuation in
            var images: [UIImage] = []
            var remaining = times.count
            
            generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
                if let cgImage {
                    images.append(UIImage(cgImage: cgImage))
                }
                remaining -= 1
                if remaining == 0 {
                    DispatchQueue.main.async {
                        self.thumbnails = images
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func seekToStart() {
        player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
    }
    
    private func cleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }
    
    private func exportTrimmedVideo() {
        isExporting = true
        exportError = nil
        
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            exportError = "Cannot create export session"
            isExporting = false
            return
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.metadata = []
        
        let isTrimmed = startTime > 0.05 || (duration - endTime) > 0.05
        if isTrimmed {
            let start = CMTime(seconds: startTime, preferredTimescale: 600)
            let end = CMTime(seconds: endTime, preferredTimescale: 600)
            exportSession.timeRange = CMTimeRange(start: start, end: end)
        }
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExporting = false
                switch exportSession.status {
                case .completed:
                    let finalDuration = isTrimmed ? self.selectedDuration : self.duration
                    self.cleanup()
                    self.onTrimmed(outputURL, finalDuration)
                case .failed:
                    self.exportError = exportSession.error?.localizedDescription ?? "Export failed"
                case .cancelled:
                    self.exportError = "Export cancelled"
                default:
                    self.exportError = "Unknown export error"
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        let frac = Int((s - Double(Int(s))) * 10)
        if mins > 0 {
            return String(format: "%d:%02d.%d", mins, secs, frac)
        }
        return String(format: "%d.%ds", secs, frac)
    }
}

// MARK: - Trim Timeline with drag handles

struct TrimTimelineView: View {
    let duration: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let maxDuration: Double
    let thumbnails: [UIImage]
    
    // Track the value at drag start so we can apply translation to it
    @GestureState private var startDragInitial: Double?
    @GestureState private var endDragInitial: Double?
    @GestureState private var selectionDragInitial: (start: Double, end: Double)?
    
    private let handleWidth: CGFloat = 16
    
    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width - (handleWidth * 2)
            let startX = (startTime / duration) * trackWidth
            let endX = (endTime / duration) * trackWidth
            
            ZStack(alignment: .leading) {
                // Thumbnail strip background
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumb in
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: (trackWidth + handleWidth * 2) / CGFloat(max(thumbnails.count, 1)))
                            .clipped()
                    }
                }
                .frame(width: trackWidth + handleWidth * 2, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Dimmed overlay for unselected regions
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: startX + handleWidth)
                    
                    Spacer()
                        .frame(width: max(0, endX - startX))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: max(0, trackWidth - endX + handleWidth))
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
                
                // Selection border
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: max(0, endX - startX) + handleWidth * 2, height: 50)
                    .offset(x: startX)
                    .allowsHitTesting(false)
                
                // Draggable selection region (between handles)
                Rectangle()
                    .fill(Color.white.opacity(0.001)) // Nearly invisible but hit-testable
                    .frame(width: max(0, endX - startX), height: 50)
                    .offset(x: startX + handleWidth)
                    .gesture(
                        DragGesture()
                            .updating($selectionDragInitial) { _, state, _ in
                                if state == nil { state = (start: startTime, end: endTime) }
                            }
                            .onChanged { value in
                                guard let initial = selectionDragInitial else { return }
                                let deltaTime = (value.translation.width / trackWidth) * duration
                                let span = initial.end - initial.start
                                
                                var newStart = initial.start + deltaTime
                                var newEnd = initial.end + deltaTime
                                
                                // Clamp to bounds while preserving span
                                if newStart < 0 {
                                    newStart = 0
                                    newEnd = span
                                }
                                if newEnd > duration {
                                    newEnd = duration
                                    newStart = duration - span
                                }
                                
                                startTime = newStart
                                endTime = newEnd
                            }
                    )
                
                // Start handle
                TrimHandle()
                    .offset(x: startX)
                    .gesture(
                        DragGesture()
                            .updating($startDragInitial) { _, state, _ in
                                if state == nil { state = startTime }
                            }
                            .onChanged { value in
                                guard let initial = startDragInitial else { return }
                                let deltaTime = (value.translation.width / trackWidth) * duration
                                var newStart = initial + deltaTime
                                newStart = max(0, newStart)
                                newStart = min(newStart, endTime - 0.5)
                                if endTime - newStart > maxDuration {
                                    newStart = endTime - maxDuration
                                }
                                startTime = newStart
                            }
                    )
                
                // End handle
                TrimHandle()
                    .offset(x: endX + handleWidth)
                    .gesture(
                        DragGesture()
                            .updating($endDragInitial) { _, state, _ in
                                if state == nil { state = endTime }
                            }
                            .onChanged { value in
                                guard let initial = endDragInitial else { return }
                                let deltaTime = (value.translation.width / trackWidth) * duration
                                var newEnd = initial + deltaTime
                                newEnd = min(newEnd, duration)
                                newEnd = max(newEnd, startTime + 0.5)
                                if newEnd - startTime > maxDuration {
                                    newEnd = startTime + maxDuration
                                }
                                endTime = newEnd
                            }
                    )
            }
        }
    }
}

struct TrimHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 16, height: 50)
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: 20)
            }
            .contentShape(Rectangle().inset(by: -10))
    }
}
