import AVFoundation
import ImageIO
import NostrEssentials
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import Nostur

struct BlossomPostMetadataTests {
    @Test func plannedMirrorsUseProcessedHashAndCanonicalServerURLs() throws {
        let processedHash = String(repeating: "ab", count: 32)
        let primary = "https://cdn.primary.example/processed.jpg"
        let plan = try #require(BlossomPostMirrorPlan(sourceURL: primary, hash: processedHash, serverStrings: [
            "https://primary.example", "https://primary.example/", "https://mirror.example/",
            "https://mirror.example", "http://insecure.example", "not a server",
            "https://second.example/path?query=1#fragment"
        ]))
        #expect(plan.sourceURL.absoluteString == primary)
        #expect(plan.hash == processedHash)
        #expect(plan.servers.map(\.absoluteString) == ["https://mirror.example", "https://second.example"])
        #expect(plan.fallbackURLs == [
            "https://mirror.example/\(processedHash).jpg", "https://second.example/\(processedHash).jpg"
        ])

        let imeta = Imeta(url: primary, hash: processedHash, fallbackURLs: plan.fallbackURLs)
        var tag = ["imeta", "url \(primary)", "sha256 \(processedHash)"]
        appendFallbackIMetaFields(for: imeta, to: &tag)
        #expect(Array(tag.suffix(2)) == plan.fallbackURLs.map { "fallback \($0)" })
    }

    @Test func missingProcessedHashCannotAdvertiseOriginalFileMirrors() {
        #expect(BlossomPostMirrorPlan(sourceURL: "https://primary.example/processed.jpg", hash: nil, serverStrings: ["https://primary.example", "https://mirror.example"]) == nil)
        #expect(BlossomPostMirrorPlan(sourceURL: "https://primary.example/processed.jpg", hash: "invalid", serverStrings: ["https://primary.example", "https://mirror.example"]) == nil)
    }

    @Test func singleServerDoesNotAddFallbacksAndDuplicateURLsAreSkipped() throws {
        let hash = String(repeating: "ab", count: 32)
        let primary = "https://primary.example/\(hash).png"
        let plan = try #require(BlossomPostMirrorPlan(sourceURL: primary, hash: hash, serverStrings: ["https://primary.example"]))
        #expect(plan.servers.isEmpty)
        #expect(plan.fallbackURLs.isEmpty)
        var tag = ["imeta", "url \(primary)"]
        appendFallbackIMetaFields(for: Imeta(url: primary, fallbackURLs: [primary, "https://mirror.example/file.png", "https://mirror.example/file.png"]), to: &tag)
        #expect(tag == ["imeta", "url \(primary)", "fallback https://mirror.example/file.png"])
    }

    @Test @MainActor func missingServerHashDoesNotBlockUploadOrUseOriginalHash() async throws {
        let original = try imageData(width: 80, height: 40, type: .png)
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://unreachable.example/processed.png","type":"image/png"}"#.utf8
        ))
        let item = BlossomUploadItem(data: original, contentType: "image/png", authorizationHeader: "", blurhash: "local-blurhash", verb: .upload)
        try await completeBlossomPostUpload(item, response: response) { _ in
            Issue.record("/upload must use local metadata without downloading")
            throw URLError(.timedOut)
        }
        #expect(item.finished)
        #expect(item.sha256processed == nil)
        #expect(item.dim == "80x40")
        #expect(item.blurhash == "local-blurhash")
    }

    @Test @MainActor func processedServerHashUsesLocalBlurhashWithoutDownload() async throws {
        let original = try imageData(width: 80, height: 40, type: .png)
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://unreachable.example/processed.png","sha256":"processed-server-hash","type":"image/png","nip94":[["dim","37.0x61.0"]]}"#.utf8
        ))
        let item = BlossomUploadItem(data: original, contentType: "image/png", authorizationHeader: "")
        try await completeBlossomPostUpload(item, response: response) { _ in
            Issue.record("Missing BlurHash must not trigger a download when /media dimensions are present")
            throw URLError(.timedOut)
        }
        #expect(item.finished)
        #expect(item.sha256processed == "processed-server-hash")
        #expect(item.sha256processed != item.sha256)
        #expect(item.dim == "37.0x61.0")
        #expect(item.blurhash?.count == 28)
    }

    @Test(arguments: [false, true]) @MainActor func serverMetadataTakesPriorityOverLocalFallbacks(useMedia: Bool) async throws {
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://example.com/original.png","sha256":"original-hash","type":"image/png","nip94":[["url","https://example.com/processed.png"],["x","processed-hash"],["dim","37.0x61.0"],["blurhash","server-blurhash"]]}"#.utf8
        ))
        let item = BlossomUploadItem(data: Data(), contentType: "image/png", authorizationHeader: "", blurhash: "local-blurhash", verb: useMedia ? .media : .upload)
        item.dim = "80x40"
        try await completeBlossomPostUpload(item, response: response) { _ in
            Issue.record("Response dimensions must avoid downloading on either endpoint")
            throw URLError(.timedOut)
        }
        #expect(item.finished)
        #expect(item.downloadUrl == "https://example.com/processed.png")
        #expect(item.sha256processed == "processed-hash")
        #expect(item.dim == "37.0x61.0")
        #expect(item.blurhash == "server-blurhash")
    }

    @Test @MainActor func mediaWithDimensionsDoesNotDownloadForMissingHashOrBlurhash() async throws {
        let original = try imageData(width: 80, height: 40, type: .png)
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://unreachable.example/processed.png","type":"image/png","nip94":[["dim","37x61"]]}"#.utf8
        ))
        let item = BlossomUploadItem(data: original, contentType: "image/png", authorizationHeader: "", verb: .media)
        try await completeBlossomPostUpload(item, response: response) { _ in
            Issue.record("Missing SHA-256 and BlurHash must not trigger a /media download")
            throw URLError(.timedOut)
        }
        #expect(item.finished)
        #expect(item.dim == "37x61")
        #expect(item.sha256processed == nil)
        #expect(item.blurhash?.count == 28)
    }

    @Test(arguments: [false, true]) @MainActor func mediaWithoutDimensionsDownloadsResizedOutput(invalidDimension: Bool) async throws {
        let original = try imageData(width: 80, height: 40, type: .png)
        let processed = try imageData(width: 37, height: 61, type: .png)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try processed.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let response = BlossomPostUploadResponse(
            url: "https://example.com/processed.png", type: "image/png",
            nip94: invalidDimension ? [NostrEssentials.Tag(["dim", "0x0"])] : nil
        )
        let item = BlossomUploadItem(data: original, contentType: "image/png", authorizationHeader: "", blurhash: "local-blurhash", verb: .media)
        item.dim = "80x40" // Known local dimensions are unsafe for the /media output.
        try await completeBlossomPostUpload(item, response: response) { request in
            #expect(request.url?.absoluteString == response.downloadURL)
            #expect(await MainActor.run { !item.finished })
            return (file, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(item.finished)
        #expect(item.dim == "37x61")
        #expect(item.sha256processed == nil)
        #expect(item.blurhash == "local-blurhash")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test @MainActor func mediaDimensionDownloadFailureDoesNotUseLocalDimensions() async throws {
        let response = BlossomPostUploadResponse(url: "https://example.com/resized.png", type: "image/png")
        let item = BlossomUploadItem(data: Data(), contentType: "image/png", authorizationHeader: "", verb: .media)
        item.dim = "80x40"
        do {
            try await completeBlossomPostUpload(item, response: response) { _ in throw URLError(.timedOut) }
            Issue.record("/media must not publish guessed dimensions after the processed-file request fails")
        }
        catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
        #expect(!item.finished)
    }

    @Test @MainActor func unavailableOptionalMetadataDoesNotFailSuccessfulUpload() async throws {
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://unreachable.example/photo.png","type":"image/png"}"#.utf8
        ))
        let item = BlossomUploadItem(data: Data(), contentType: "image/png", authorizationHeader: "", verb: .upload)
        try await completeBlossomPostUpload(item, response: response)
        #expect(item.finished)
        #expect(item.sha256processed == nil)
        #expect(item.dim == nil)
        #expect(item.blurhash == nil)
    }

    @Test(arguments: [1, 6, 8])
    func respectsLocalImageOrientation(orientation: Int) async throws {
        let data = try imageData(width: 37, height: 61, type: .jpeg, orientation: orientation)
        let metadata = try await BlossomPostMetadata().completing(fromLocalData: data, contentType: "image/jpeg")
        #expect(metadata.dim == (orientation == 1 ? "37x61" : "61x37"))
        #expect(metadata.blurhash != nil)
        #expect(metadata.hash == nil)
    }

    @Test func usesLocalGIFCanvasAndFirstFrame() async throws {
        let data = try imageData(width: 37, height: 61, type: .gif)
        let metadata = try await BlossomPostMetadata().completing(fromLocalData: data, contentType: "image/gif")
        #expect(metadata.dim == "37x61")
        #expect(metadata.blurhash != nil)
        #expect(metadata.hash == nil)
    }

    @Test func audioDoesNotRequireVisualMetadataOrHash() async throws {
        let metadata = try await BlossomPostMetadata().completing(fromLocalData: Data("test audio bytes".utf8), contentType: "audio/mp4")
        #expect(metadata.hash == nil)
        #expect(metadata.dim == nil)
        #expect(metadata.blurhash == nil)
    }

    @Test func cancelledUploadDoesNotFinishMetadata() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await BlossomPostMetadata().completing(fromLocalData: Data(), contentType: "image/png")
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled upload must not finish its metadata")
        }
        catch {
            #expect(error is CancellationError)
        }
    }

    @Test func readsRotatedVideoDimensionsAndThumbnail() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 48, AVVideoHeightKey: 32
        ])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 48, kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 48, 32, kCVPixelFormatType_32ARGB, nil, &pixelBuffer) == kCVReturnSuccess)
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 120, CVPixelBufferGetBytesPerRow(buffer) * 32)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        #expect(adaptor.append(buffer, withPresentationTime: .zero))
        #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        let metadata = try await BlossomPostMetadata().completing(fromLocalData: Data(contentsOf: file), contentType: "video/mp4")
        #expect(metadata.dim == "32x48")
        #expect(metadata.hash == nil)
        #expect(metadata.blurhash?.count == 28)
    }

    private func imageData(width: Int, height: Int, type: UTType, orientation: Int = 1) throws -> Data {
        let pixels = Data(repeating: 120, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
