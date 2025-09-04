//
//  EmbeddedVideoVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2025.
//

import SwiftUI
import AVFoundation
import NukeUI
import Nuke
import NukeVideo
import Combine

class EmbeddedVideoVM: ObservableObject {
    @Published var viewState: ViewState = .initial
    @Published var downloadProgress: Int = 0
    
    @Published var isMuted = false
    
    
    private var videoUrl: URL?
    private var videoUrlString: String?
    private var metaDimensions: CGSize?
    private var availableWidth: CGFloat?
    private var availableHeight: CGFloat?
    
    private var scaledDimensions: CGSize?
    
    public var aspect: CGFloat = 16/9
    
    private var nrPost: NRPost?
    
    public var cachedFirstFrame: CachedFirstFrame?
    
    public var isStream: Bool {
        guard let videoUrlString else { return false }
        return videoUrlString.suffix(4) == "m3u8"
    }
    
    @Published var isAudio: Bool = false
    
    
    public func load(_ url: URL, nrPost: NRPost? = nil, autoLoad: Bool = false, metaDimensions: CGSize? = nil, availableWidth: CGFloat? = nil, availableHeight: CGFloat = DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, loadAnyway: Bool = false) {
        self.videoUrl = url
        self.videoUrlString = url.absoluteString
        self.metaDimensions = metaDimensions
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.nrPost = nrPost
        
        if let metaDimensions, let availableWidth {
            self.scaledDimensions = Nostur.scaledToFit(metaDimensions, scale: 1.0, maxWidth: availableWidth, maxHeight: availableHeight)
        }
        
        guard let videoUrlString, let videoUrl else { return }
        
        self.isAudio = videoUrlString.suffix(3) == "m4a" || videoUrlString.suffix(3) == "mp3"
        
        // Already playing this url? Show PIP icon
        if AnyPlayerModel.shared.isPlaying, let currentlyPlayingUrl = AnyPlayerModel.shared.currentlyPlayingUrl, currentlyPlayingUrl == videoUrlString {
            self.viewState = .playingInPIP
            return
        }

        // Do we have the first frame cached?
        if let cachedFirstFrame = AVAssetCache.shared.getFirstFrame(url: videoUrlString) {
            self.viewState = .loadedFirstFrame(cachedFirstFrame)
            self.cachedFirstFrame = cachedFirstFrame // need to keep it to revert back to after PIP
        }
        // Warning if NSWF
        else if !loadAnyway && (nrPost?.isNSFW ?? false) {
            self.viewState = .nsfwWarning(url.absoluteString)
        }
        // Warning if no https
        else if !loadAnyway && videoUrlString.prefix(7) == "http://" {
            self.viewState = .noHttpsWarning(videoUrlString)
        }
        // Don't load if we are in low data mode
        else if !loadAnyway && SettingsStore.shared.lowDataMode {
            self.viewState = .lowDataMode(videoUrlString)
        }
        else if isStream { // For streams, try to get type of steam first
            Task {
                await loadStream(videoUrl)
            }
        }
        else if AVAssetCache.shared.failedFirstFrameUrls.contains(videoUrlString) {
            // Don't try to load first frame again if we already failed recently
            self.viewState = .noPreviewFound(videoUrlString)
        }
        else if loadAnyway { // Download full video
            Task { @MainActor in
                playUrl(videoUrl)
            }
        }
        else { // OK, lets load first frame
            Task {
                await loadFirstFrame(videoUrl)
            }
        }
    }
    
    // Show "pip logo" and play in floating/fullscreen player
    @MainActor
    fileprivate func playUrl(_ videoUrl: URL) {
        let cachedFirstFrame: CachedFirstFrame? = if case .loadedFirstFrame(let firstFrame) = self.viewState {
            firstFrame
        } else { nil }
        self.viewState = .playingInPIP
        AnyPlayerModel.shared.isShown = true // <-- need here or SwiftUI doesn't update fast enough
        guard let videoUrlString else { return }
        Task { @MainActor in
            await AnyPlayerModel.shared.loadVideo(url: videoUrlString, nrPost: self.nrPost, cachedFirstFrame: cachedFirstFrame)
        }
//        self.timeControlStatus = .playing
    }
    
    @MainActor
    public func startPlaying() {
        guard let videoUrl else { return }
        playUrl(videoUrl)
    }
    
    @MainActor
    public func pause() {
        viewState = .paused(self.downloadProgress)
    }
    
    @MainActor
    public func restoreToFirstFrame(cachedFirstFrame cachedFirstFrameFromPIP: CachedFirstFrame? = nil) {
        if let cachedFirstFrameFromPIP {
            self.downloadProgress = 0
            self.viewState = .loadedFirstFrame(cachedFirstFrameFromPIP)
        }
        else {
            guard let videoUrl else { return }
            self.viewState = .noPreviewFound(videoUrl.absoluteString)
        }
    }
    
    @MainActor
    public func loadNonHttpsAnyway() {
        
    }
    
    private func loadStream(_ videoURL: URL) async {
        let streamType: StreamType? = try? await fetchStreamType(videoURL)
        
        Task { @MainActor in
            if streamType == .unknown { // probably audio
                self.isAudio = true
            }
            Task {
                await loadFirstFrame(videoURL)
            }
        }
    }
    
    private func fetchStreamType(_ videoURL: URL) async throws -> StreamType {
        return try await withCheckedThrowingContinuation { continuation in
            Nostur.fetchStreamType(url: videoURL) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    private func loadFirstFrame(_ videoURL: URL) async {
        do {
            // Probe file size, following redirects if needed
            let (actualUrl, fileSize) = try await getFileSizeWithRedirects(videoURL, maxRedirects: 3) ?? (videoURL, 1_048_576) // Default to 1MB if unknown
            
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
                let (data, response) = try await URLSession.shared.data(for: rangedRequest(url: actualUrl, bytes: range))
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
#if DEBUG
                    L.og.debug("🎞️ statusCode not 206 or 200, got \(String(describing: response)) on \(actualUrl)")
#endif
                    throw URLError(.badServerResponse)
                }
                
                combinedData.append(data)
                
                // Try extracting the frame, but don’t throw yet
                do {
                    if let (image, duration, dim) = try await tryExtractFirstFrameDetails(from: combinedData) {
                        await MainActor.run { [weak self] in
                            let cachedFirstFrame = CachedFirstFrame(url: videoURL.absoluteString, uiImage: image, dimensions: dim, duration: duration)
                            self?.viewState = .loadedFirstFrame(cachedFirstFrame)
                            self?.cachedFirstFrame = cachedFirstFrame // need to keep it to revert back to after PIP
                            AVAssetCache.shared.set(url: videoURL.absoluteString, firstFrame: cachedFirstFrame)
#if DEBUG
                            L.og.debug("🎞️ Successful firstFrame \(String(describing: dim)) \(cachedFirstFrame.durationString ?? "") on \(videoURL.absoluteString) -[LOG]-")
#endif
                        }
                        return // Success, exit
                    }
                } catch {
#if DEBUG
                    L.og.debug("🎞️ Frame extraction failed at \(combinedData.count) bytes on \(actualUrl) -[LOG]-")
#endif
                    // Only throw if it’s the last range
                    if index == frontRanges.count - 1 {
#if DEBUG
                        L.og.debug("🎞️ All front ranges failed, trying end of file -[LOG]-")
#endif
                        break
                    }
                    // Otherwise, continue to next range
                }
            }
            
            // If front ranges fail, try last 1MB
            combinedData = Data() // Reset
            let endRange = max(0, fileSize - 1_048_576)..<fileSize
            let (endData, response) = try await URLSession.shared.data(for: rangedRequest(url: actualUrl, bytes: endRange))
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
#if DEBUG
                L.og.debug("🎞️ statusCode not 206 or 200, got \(String(describing: response)) on \(actualUrl) -[LOG]-")
#endif
                throw URLError(.badServerResponse)
            }
            
            combinedData.append(endData)
            
            do {
                if let (image, duration, dim) = try await tryExtractFirstFrameDetails(from: combinedData) {
                    await MainActor.run { [weak self] in
                        let cachedFirstFrame = CachedFirstFrame(url: videoURL.absoluteString, uiImage: image, dimensions: dim, duration: duration)
                        self?.viewState = .loadedFirstFrame(cachedFirstFrame)
                        self?.cachedFirstFrame = cachedFirstFrame // need to keep it to revert back to after PIP
                        AVAssetCache.shared.set(url: videoURL.absoluteString, firstFrame: cachedFirstFrame)
#if DEBUG
                        L.og.debug("🎞️ Successful firstFrame \(String(describing: dim)) \(cachedFirstFrame.durationString ?? "") on \(videoURL.absoluteString) -[LOG]-")
#endif
                    }
                    return
                }
            } catch {
#if DEBUG
                L.og.debug("🎞️ End extraction failed at \(combinedData.count) bytes: \(error) at \(actualUrl) -[LOG]-")
#endif
                throw error // Final failure
            }
            
        } catch {
            await MainActor.run {
#if DEBUG
                L.og.debug("🎞️ Error loading first frame: \(error.localizedDescription) at \(videoURL.absoluteString)")
#endif
                // Can't get first frame, handle as streaming...
                AVAssetCache.shared.failedFirstFrameUrls.insert(videoURL.absoluteString)
                self.viewState = .noPreviewFound(videoURL.absoluteString)
            }
        }
    }
    
    private func getFileSizeWithRedirects(_ videoURL: URL, maxRedirects: Int) async throws -> (URL, Int)? {
        var currentURL = videoURL
        var redirects = 0
        
        // Step 1: Try HEAD first
        var request = URLRequest(url: currentURL)
        request.httpMethod = "HEAD"
        let (_, headResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = headResponse as? HTTPURLResponse,
           let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let size = Int(contentLength), size != 0 {
#if DEBUG
            L.og.debug("🎞️ HEAD succeeded with Content-Length: \(size) on \(currentURL) -[LOG]-")
#endif
            return (currentURL, size)
        }
        
#if DEBUG
        L.og.debug("🎞️ HEAD returned no Content-Length or 0, falling back to GET: \(String(describing: headResponse)) on \(currentURL) -[LOG]-")
#endif
        // Step 2: Fall back to small GET to detect redirect
        while redirects < maxRedirects {
            var getRequest = URLRequest(url: currentURL)
            getRequest.httpMethod = "GET"
            getRequest.setValue("bytes=0-1023", forHTTPHeaderField: "Range") // Fetch only 1KB
            
            let (_, getResponse) = try await Self.noRedirectSession.data(for: getRequest)
            
            guard let httpResponse = getResponse as? HTTPURLResponse else {
#if DEBUG
                L.og.debug("🎞️ GET failed, no HTTP response on \(currentURL)")
#endif
                return nil
            }
            
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
                httpResponse.statusCode == 206,
                let sizeString = contentRange.components(separatedBy: "/").last,
                let size = Int(sizeString), size > 0 {
                return (currentURL, size)
            }
 
            // Check for redirect
            if (300...399).contains(httpResponse.statusCode),
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let newURL = URL(string: location, relativeTo: currentURL) {
#if DEBUG
                L.og.debug("🎞️ GET redirected from \(currentURL) to \(newURL)")
#endif
                currentURL = newURL
                
                // Step 3: Do HEAD on the redirected URL
                var redirectedHeadRequest = URLRequest(url: currentURL)
                redirectedHeadRequest.httpMethod = "HEAD"
                let (_, redirectedHeadResponse) = try await URLSession.shared.data(for: redirectedHeadRequest)
                
                if let redirectedHttpResponse = redirectedHeadResponse as? HTTPURLResponse,
                   let contentLength = redirectedHttpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let size = Int(contentLength) {
#if DEBUG
                    L.og.debug("🎞️ HEAD on redirected URL succeeded with Content-Length: \(size) on \(currentURL)")
#endif
                    return (currentURL, size)
                }
         
#if DEBUG
                L.og.debug("🎞️ HEAD on redirected URL returned no Content-Length: \(String(describing: redirectedHeadResponse)) on \(currentURL)")
#endif
                redirects += 1
                continue
            }
            
            // If GET succeeds but no redirect or Content-Length, give up
#if DEBUG
            L.og.debug("🎞️ GET returned no redirect or Content-Length: \(String(describing: getResponse)) on \(currentURL)")
#endif
            return nil
        }
        
#if DEBUG
        L.og.debug("🎞️ getFileSizeWithRedirects() exceeded max redirects (\(maxRedirects)) on \(currentURL) -[LOG]-")
#endif
        return nil // Too many redirects or no Content-Length
    }
    
    private func tryExtractFirstFrameDetails(from data: Data) async throws -> (UIImage, CMTime?, CGSize?)? {
        guard let videoUrl else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(videoUrl.pathExtension.isEmpty ? "mp4" : videoUrl.pathExtension)
        
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
    
    private func rangedRequest(url: URL, bytes: Range<Int>) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("bytes=\(bytes.lowerBound)-\(bytes.upperBound-1)", forHTTPHeaderField: "Range")
        return request
    }
    
    // Custom URLSession with delegate to handle redirects
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()
}

extension EmbeddedVideoVM {
    enum ViewState {
        case initial
        case loading(Int)
        case paused(Int)
        case noHttpsWarning(String)
        case nsfwWarning(String)
        case lowDataMode(String)
        case loadedFirstFrame(CachedFirstFrame)
        case noPreviewFound(String)
        case playingInPIP
        case error(String)
    }
}

// Delegate to disable automatic redirect following
private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Return nil to prevent automatic redirect
        completionHandler(nil)
    }
}

// Fetch and parse meta og tags
func fetchStreamType(url: URL, completion: @escaping (Result<StreamType, Error>) -> Void) {
    let request = URLRequest(url: url)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data, error == nil else {
            completion(.failure(error!))
            return
        }
        guard let content = String(data: data, encoding: .utf8) else {
            completion(.failure(NSError(domain: "Invalid", code: 0, userInfo: nil)))
            return
        }
        
        DispatchQueue.global().async {
            completion(.success(detectStreamType(content)))
        }
    }
    task.resume()
}

public enum StreamType {
    case video
//    case audio
    case unknown
}

func detectStreamType(_ content: String) -> StreamType {
    let content = content.prefix(3000)
    if content.contains("RESOLUTION=") {
        return .video
    }
    else if content.contains("FRAME-RATE=") {
        return .video
    }
    else if content.contains("PLAYLIST-TYPE:VOD") {
        return .video
    }
    else if content.contains(".ts") {
        return .video
    }
    return .unknown // probably audio
}
