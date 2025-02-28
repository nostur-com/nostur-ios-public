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

class EmbeddedVideoVM: ObservableObject {
    @Published var viewState: ViewState = .initial
    @Published var downloadProgress: Int = 0
    private var downloadTask: AsyncImageTask?
    
    private var videoUrl: URL?
    private var videoUrlString: String?
    private var metaDimensions: CGSize?
    private var availableWidth: CGFloat?
    private var availableHeight: CGFloat?
    
    private var scaledDimensions: CGSize?
    
    public var aspect: CGFloat = 16/9
    
    private var nrPost: NRPost?
    
    public var cachedFirstFrame: CachedFirstFrame?
    
    private var isStream: Bool {
        guard let videoUrlString else { return false }
        return videoUrlString.suffix(4) == "m3u8" || videoUrlString.suffix(3) == "m4a" || videoUrlString.suffix(3) == "mp3"
    }
    
    
    public func load(_ url: URL, nrPost: NRPost? = nil, autoLoad: Bool = false, metaDimensions: CGSize? = nil, availableWidth: CGFloat? = nil, availableHeight: CGFloat = DIMENSIONS.MAX_MEDIA_ROW_HEIGHT) {
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
        
        // Already playing this url? Show PIP icon
        if AnyPlayerModel.shared.isPlaying, let currentlyPlayingUrl = AnyPlayerModel.shared.currentlyPlayingUrl, currentlyPlayingUrl == videoUrlString {
            self.viewState = .playingInPIP
            return
        }
        
        // Do we have the fully cached video?
        if let cachedVideo = AVAssetCache.shared.get(url: videoUrlString) {
            self.viewState = .loadedFullVideo(cachedVideo)
        }
        // Do we have the first frame cached?
        else if let cachedFirstFrame = AVAssetCache.shared.getFirstFrame(url: videoUrlString) {
            self.viewState = .loadedFirstFrame(cachedFirstFrame)
            self.cachedFirstFrame = cachedFirstFrame // need to keep it to revert back to after PIP
        }
        // Warning if no https
        else if videoUrlString.prefix(7) == "http://" {
            self.viewState = .noHttpsWarning(videoUrlString)
        }
        // Don't load if we are in low data mode
        else if SettingsStore.shared.lowDataMode {
            self.viewState = .lowDataMode(videoUrlString)
        }
        else { // OK, lets load first frame
            Task {
                await loadFirstFrame(videoUrl)
            }
        }
    }
    
    
    // Play in embedded video on macOS/iPad or show "pip logo" and play in  floating/fullscreen player on iPhone
    @MainActor
    fileprivate func playCachedVideo(_ cachedVideo: CachedVideo) {
        if IS_IPHONE { // Play in new fullscreen/floating player
            self.viewState = .playingInPIP
            AnyPlayerModel.shared.loadVideo(cachedVideo: cachedVideo, nrPost: self.nrPost)
        }
        else { // Play in old embedded player
            self.viewState = .loadedFullVideo(cachedVideo)
        }
    }
    
    // Play in embedded video on macOS/iPad or show "pip logo" and play in floating/fullscreen player on iPhone
    @MainActor
    fileprivate func playStreamUrl(_ videoUrl: URL) {
        if IS_IPHONE { // Play in new fullscreen/floating player
            self.viewState = .playingInPIP
            guard let videoUrlString else { return }
            Task { @MainActor in
                await AnyPlayerModel.shared.loadVideo(url: videoUrlString, nrPost: self.nrPost)
            }
        }
        else { // open stream url view in old embedded player
            self.viewState = .streaming(videoUrl)
        }
    }
    
    @MainActor
    public func startPlaying() {
        guard let videoUrl, let videoUrlString else { return }
        if let cachedVideo = AVAssetCache.shared.get(url: videoUrlString) {
            playCachedVideo(cachedVideo)
        }
        
        if isStream {
            playStreamUrl(videoUrl)
        }
        else { // start downloading video
            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                await self.downloadVideo()
            }
        }
    }
    
    @MainActor
    public func cancel() {
        downloadTask?.cancel()
    }
    
    @MainActor
    public func didStopPlaying() {
        if let cachedFirstFrame {
            self.downloadProgress = 0
            self.viewState = .loadedFirstFrame(cachedFirstFrame)
        }
    }
    
    @MainActor
    public func loadNonHttpsAnyway() {
        
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
                        L.og.debug("🎞️ All front ranges failed, trying end of file -[LOG]-")
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
                L.og.debug("🎞️ GET failed, no HTTP response on \(currentURL)")
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
                L.og.debug("🎞️ GET redirected from \(currentURL) to \(newURL)")
                currentURL = newURL
                
                // Step 3: Do HEAD on the redirected URL
                var redirectedHeadRequest = URLRequest(url: currentURL)
                redirectedHeadRequest.httpMethod = "HEAD"
                let (_, redirectedHeadResponse) = try await URLSession.shared.data(for: redirectedHeadRequest)
                
                if let redirectedHttpResponse = redirectedHeadResponse as? HTTPURLResponse,
                   let contentLength = redirectedHttpResponse.value(forHTTPHeaderField: "Content-Length"),
                   let size = Int(contentLength) {
                    L.og.debug("🎞️ HEAD on redirected URL succeeded with Content-Length: \(size) on \(currentURL)")
                    return (currentURL, size)
                }
                
                L.og.debug("🎞️ HEAD on redirected URL returned no Content-Length: \(String(describing: redirectedHeadResponse)) on \(currentURL)")
                redirects += 1
                continue
            }
            
            // If GET succeeds but no redirect or Content-Length, give up
            L.og.debug("🎞️ GET returned no redirect or Content-Length: \(String(describing: getResponse)) on \(currentURL)")
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
    
    private func downloadVideo() async {
        guard let videoUrl, let videoUrlString else { return }
        self.downloadTask = ImageProcessing.shared.video.imageTask(with: videoUrl)
        let availableWidth = self.availableWidth ?? UIScreen.main.bounds.width
        
        if let downloadTask {
//            DispatchQueue.main.async {
//                videoState = .loading
//            }
            for await progress in downloadTask.progress {
                let percent = Int(ceil(progress.fraction * 100))
                if percent % 3 == 0 { // only update view every 3 percent for performance
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = percent
                    }
                }
            }
        }
        
        if let response = try? await downloadTask?.response {
            if let type = response.container.type, type.isVideo, let asset = response.container.userInfo[.videoAssetKey] as? AVAsset {
                Task.detached(priority: .background) { [weak self] in
                    guard let self else { return }
                    if let videoSize = await getVideoDimensions(asset: asset) {
                        
                        let scaledDimensions = Nostur.scaledToFit(videoSize, scale: 1, maxWidth: availableWidth, maxHeight: self.availableHeight ?? DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        
                        
                        let firstFrame: UIImage? = if case .loadedFirstFrame(let cachedFirstFrame) = viewState {
                            cachedFirstFrame.uiImage
                        } else {
                            nil
                        }
                        
                        let cachedVideo = CachedVideo(url: videoUrlString, asset: asset,
                                                      dimensions: videoSize,
                                                      scaledDimensions: scaledDimensions, videoLength: "--:--", firstFrame: firstFrame)
                        AVAssetCache.shared.set(url: videoUrlString, asset: cachedVideo)
                        
                        Task { @MainActor [weak self] in
                            self?.playCachedVideo(cachedVideo)
                        }
                    }
                    else {
                        Task { @MainActor [weak self] in
                            self?.viewState = .error("Error downloading video")
                        }
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    Task { @MainActor [weak self] in
                        self?.viewState = .error("Error downloading video")
                    }
                }
            }
        }
    }
    
}

extension EmbeddedVideoVM {
    enum ViewState {
        case initial
        case noHttpsWarning(String)
        case loading(Int)
        case cancelled
        case lowDataMode(String)
        case loadedFirstFrame(CachedFirstFrame)
        case loadedFullVideo(CachedVideo)
        case streaming(URL)
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
