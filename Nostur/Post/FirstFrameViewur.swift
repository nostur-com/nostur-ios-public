//
//  VideoFrameView.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2025.
//

import SwiftUI
import AVFoundation

import SwiftUI
import AVFoundation

struct FirstFrameViewur: View {
    @State private var firstFrame: CachedFirstFrame?
    
    public let videoURL: URL
    public let videoWidth: CGFloat
    public var theme: Theme
    
    // Custom URLSession with delegate to handle redirects
    private static let noRedirectSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()
    
    var body: some View {
        VStack {
            if let firstFrame = firstFrame {
                if let dimensions = firstFrame.dimensions {
                    let scaledDimensions = Nostur.scaledToFit(dimensions, scale: 1.0, maxWidth: videoWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                    theme.lineColor.opacity(0.5)
                        .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                        .overlay {
                            Image(uiImage: firstFrame.uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                                .overlay(alignment: .bottomLeading) {
                                    if let durationString = firstFrame.durationString {
                                        Text(durationString)
                                            .foregroundColor(.white)
                                            .fontWeight(.bold)
                                            .padding(3)
                                            .background(.black)
                                            .padding(5)
                                    }
                                }
                        }
                }
                else {
                    Image(uiImage: firstFrame.uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: videoWidth, height: videoWidth * 9/16)
                }
            } else {
                ProgressView()
                    .frame(width: videoWidth, height: videoWidth * 9/16)
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
            // Probe file size, following redirects if needed
            let (actualUrl, fileSize) = try await getFileSizeWithRedirects(maxRedirects: 3) ?? (videoURL, 1_048_576) // Default to 1MB if unknown
            
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
                        await MainActor.run {
                            let cachedFirstFrame = CachedFirstFrame(url: videoURL.absoluteString, uiImage: image, dimensions: dim, duration: duration)
                            self.firstFrame = cachedFirstFrame
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
                    await MainActor.run {
                        let cachedFirstFrame = CachedFirstFrame(url: videoURL.absoluteString, uiImage: image, dimensions: dim, duration: duration)
                        self.firstFrame = cachedFirstFrame
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
    
    private func getFileSizeWithRedirects(maxRedirects: Int) async throws -> (URL, Int)? {
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
    
    private func rangedRequest(url: URL, bytes: Range<Int>) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("bytes=\(bytes.lowerBound)-\(bytes.upperBound-1)", forHTTPHeaderField: "Range")
        return request
    }
    
    private func getVideoDimensions(asset: AVAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let size = try? await track.load(.naturalSize)
        return size
    }
}

// Delegate to disable automatic redirect following
private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Return nil to prevent automatic redirect
        completionHandler(nil)
    }
}


#Preview {
//    FirstFrameViewur(videoURL: URL(string: "https://file-examples.com/storage/fe1b07b09f67bcb9b96354c/2017/04/file_example_MP4_1920_18MG.mp4")!, videoWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
    FirstFrameViewur(videoURL: URL(string: "https://m.primal.net/OEzS.mp4")!, videoWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
}

class Redirect : NSObject {
    var session: URLSession?
    
    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    func makeRequest() {
        let url = URL(string: "http://gmail.com")!
        let task = session?.dataTask(with: url) {(data, response, error) in
            guard let data = data else {
                return
            }
            print(String(data: data, encoding: .utf8)!)
        }
        task?.resume()
    }
}

extension Redirect: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Stops the redirection, and returns (internally) the response body.
        completionHandler(nil)
    }
}
