//
//  VideoFrameView.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2025.
//

import SwiftUI
import AVFoundation

struct FirstFrameViewur: View {
    @State private var firstFrame: UIImage?
    @State private var duration: CMTime?
    @State private var scaledDimensions: CGSize?
    @State private var errorMessages: [String] = []
    
    let videoURL: URL
    let videoWidth: CGFloat
    
    private var durationString: String? {
        guard let duration else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        let secondsText = String(format: "%02d", Int(seconds) % 60)
        let minutesText = String(format: "%02d", Int(seconds) / 60)
        return "\(minutesText):\(secondsText)"
    }
    
    var body: some View {
        VStack {
            ForEach(errorMessages.indices, id:\.self) { index in
                Text(errorMessages[index])
            }
            if let image = firstFrame {
                if let scaledDimensions {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .overlay(alignment: .bottomLeading) {
                            if let durationString {
                                Text(durationString)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)
                                    .padding(3)
                                    .background(.black)
                                    .padding(5)
                            }
                        }
                }
                else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if let cachedFrame = AVAssetCache.shared.getFirstFrame(url: videoURL.absoluteString) {
                self.firstFrame = cachedFrame
            }
            else {
                await loadFirstFrame()
            }
        }
    }
    
    private func loadFirstFrame() async {
        do {
            // Probe file size with HEAD request
            let fileSize = try await getFileSize()
            
            // Define progressive ranges: 128KB, 256KB, 512KB, 1024KB
            var frontRanges = [
                0..<min(131_072, fileSize)  // 128KB
            ]
            
            if fileSize > 131_072 { // 128KB to 256KB
                frontRanges.append(131_072..<min(262_144, fileSize))
            }
            if fileSize > 262_144 {  // 256KB to 512KB
                frontRanges.append(262_144..<min(524_288, fileSize))
            }
            if fileSize > 524_288 { // 512KB to 1024KB
                frontRanges.append(524_288..<min(1_048_576, fileSize))
            }
            
            var combinedData = Data()
            
            for (index, range) in frontRanges.enumerated() {
                // Fetch the next chunk
                let (data, response) = try await URLSession.shared.data(for: rangedRequest(url: videoURL, bytes: range))
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 206 else {
                    throw URLError(.badServerResponse)
                }
                
                combinedData.append(data)
                
                // Try extracting the frame, but don’t throw yet
                do {
                    if let (image, duration, dim) = try await tryExtractFirstFrameDetails(from: combinedData) {
                        await MainActor.run {
                            firstFrame = image
                            AVAssetCache.shared.set(url: videoURL.absoluteString, firstFrame: image)
                            self.duration = duration
                        }
                        return // Success, exit
                    }
                } catch {
                    L.og.debug("🎞️ Frame extraction failed at \(combinedData.count) bytes: \(error)")
                    errorMessages.append("🎞️ Frame extraction failed at \(combinedData.count) bytes: \(error)")
                    // Only throw if it’s the last range
                    if index == frontRanges.count - 1 {
                        L.og.debug("🎞️ All front ranges failed, trying end of file")
                        errorMessages.append("All front ranges failed, trying end of file")
                        break
                    }
                    // Otherwise, continue to next range
                }
            }
            
            // If front ranges fail, try last 1MB
            combinedData = Data() // Reset
            let endRange = max(0, fileSize - 1_048_576)..<fileSize
            let (endData, response) = try await URLSession.shared.data(for: rangedRequest(url: videoURL, bytes: endRange))
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }
            
            combinedData.append(endData)
            
            do {
                if let (image, duration, dim) = try await tryExtractFirstFrameDetails(from: combinedData) {
                    await MainActor.run {
                        firstFrame = image
                        self.duration = duration
                    }
                    return
                }
            } catch {
                L.og.debug("🎞️ End extraction failed at \(combinedData.count) bytes: \(error)")
                errorMessages.append("🎞️ End extraction failed at \(combinedData.count) bytes: \(error)")
                throw error // Final failure
            }
            
        } catch {
            await MainActor.run {
                errorMessages.append("🎞️ Error loading first frame: \(error.localizedDescription)")
            }
        }
    }
    
    private func tryExtractFirstFrameDetails(from data: Data) async throws -> (UIImage, CMTime?, CGSize?)? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension)
        
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try data.write(to: tempURL)
        let asset = AVAsset(url: tempURL)
        
        // Check if asset is valid by getting duration
        let duration = try await asset.load(.duration)
        if duration == .zero || duration == .indefinite {
            return nil // Not enough data yet
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let dim: CGSize? = await getVideoDimensions(asset: asset)
        
        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        return (UIImage(cgImage: cgImage), duration, dim)
    }
    
    private func getFileSize() async throws -> Int {
        var request = URLRequest(url: videoURL)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
              let size = Int(contentLength) else {
            throw URLError(.badServerResponse)
        }
        return size
    }
    
    private func rangedRequest(url: URL, bytes: Range<Int>) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("bytes=\(bytes.lowerBound)-\(bytes.upperBound-1)", forHTTPHeaderField: "Range")
        return request
    }
}


#Preview {
//    FirstFrameViewur(videoURL: URL(string: "https://file-examples.com/storage/fe1b07b09f67bcb9b96354c/2017/04/file_example_MP4_1920_18MG.mp4")!, videoWidth: UIScreen.main.bounds.width)
    FirstFrameViewur(videoURL: URL(string: "https://m.primal.net/OEzS.mp4")!, videoWidth: UIScreen.main.bounds.width)
}
