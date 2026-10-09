import AVFoundation
import CryptoKit
import ImageIO
import NostrEssentials
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import Nostur

struct BlossomPostMetadataTests {
    @Test @MainActor func uploadWithoutHashWaitsForReturnedFileMetadata() async throws {
        let original = try imageData(width: 80, height: 40, type: .png)
        let processed = try imageData(width: 37, height: 61, type: .png)
        let file = try temporaryFile(processed)
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://blossom.primal.net/processed.png","type":"image/png"}"#.utf8
        ))
        let item = BlossomUploadItem(data: original, contentType: "image/png", authorizationHeader: "", blurhash: "original-blurhash")
        try await completeBlossomPostUpload(item, response: response) { request in
            #expect(request.url?.absoluteString == response.downloadURL)
            let finished = await MainActor.run { item.finished }
            #expect(!finished)
            return (file, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(item.finished)
        #expect(item.dim == "37x61")
        #expect(item.sha256processed == Data(SHA256.hash(data: processed)).map { String(format: "%02x", $0) }.joined())
        #expect(item.sha256processed != item.sha256)
        #expect(item.blurhash != "original-blurhash")
        #expect(item.blurhash?.count == 28)
    }

    @Test @MainActor func serverMetadataAvoidsFallbackAndPreservesDecimalDimensions() async throws {
        let response = try JSONDecoder().decode(BlossomPostUploadResponse.self, from: Data(
            #"{"url":"https://example.com/original.png","sha256":"original-hash","type":"image/png","nip94":[["url","https://example.com/processed.png"],["x","processed-hash"],["dim","37.0x61.0"],["blurhash","server-blurhash"]]}"#.utf8
        ))
        let item = BlossomUploadItem(data: Data(), contentType: "image/png", authorizationHeader: "")
        try await completeBlossomPostUpload(item, response: response) { _ in
            Issue.record("All server fields are present; no download is needed")
            throw URLError(.cancelled)
        }
        #expect(item.downloadUrl == "https://example.com/processed.png")
        #expect(item.sha256processed == "processed-hash")
        #expect(item.dim == "37.0x61.0")
        #expect(item.blurhash == "server-blurhash")
    }

    @Test func fillsMetadataFromReturnedFile() async throws {
        // The server's file differs from the original upload; inspect its URL and bytes.
        let data = try imageData(width: 37, height: 61, type: .png)
        let file = try temporaryFile(data)
        let url = URL(string: "https://blossom.primal.net/processed.png")!
        let metadata = try await BlossomPostMetadata().completing(from: url, contentType: "image/png") { request in
            #expect(request.url == url)
            return (file, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(metadata.hash == Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined())
        #expect(metadata.dim == "37x61")
        #expect(metadata.blurhash?.count == 28)
        #expect(UIImage(blurHash: try #require(metadata.blurhash), size: CGSize(width: 16, height: 16)) != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func preservesExistingServerFieldsWhileFillingMissingOnes() async throws {
        let file = try temporaryFile(imageData(width: 37, height: 61, type: .png))
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = try await BlossomPostMetadata(hash: "server-hash", dim: "37.0x61.0")
            .fillingMissingFields(from: file, contentType: "image/png")
        #expect(metadata.hash == "server-hash")
        #expect(metadata.dim == "37.0x61.0")
        #expect(metadata.blurhash != nil)
    }

    @Test func completeMetadataSkipsDownload() async throws {
        let original = BlossomPostMetadata(hash: "server-hash", dim: "37x61", blurhash: "server-blurhash")
        let metadata = try await original.completing(from: URL(string: "https://example.com/image.png")!, contentType: "image/png") { _ in
            Issue.record("Complete metadata must not download again")
            throw URLError(.cancelled)
        }
        #expect(metadata.hash == original.hash)
        #expect(metadata.dim == original.dim)
        #expect(metadata.blurhash == original.blurhash)
    }

    @Test func rejectsFailedDownloadInsteadOfPublishingIncompleteMetadata() async throws {
        let file = try temporaryFile(Data("not an image".utf8))
        let url = URL(string: "https://example.com/image.png")!
        do {
            _ = try await BlossomPostMetadata().completing(from: url, contentType: "image/png") { _ in
                (file, HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            Issue.record("An HTTP failure must not succeed as complete metadata")
        }
        catch {
            #expect((error as? URLError)?.code == .badServerResponse)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test(arguments: [1, 6, 8])
    func respectsImageOrientation(orientation: Int) async throws {
        let file = try temporaryFile(imageData(width: 37, height: 61, type: .jpeg, orientation: orientation))
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = try await BlossomPostMetadata().fillingMissingFields(from: file, contentType: "image/jpeg")
        #expect(metadata.dim == (orientation == 1 ? "37x61" : "61x37"))
        #expect(metadata.blurhash != nil)
    }

    @Test func usesGIFCanvasAndFirstFrame() async throws {
        let file = try temporaryFile(imageData(width: 37, height: 61, type: .gif))
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = try await BlossomPostMetadata().fillingMissingFields(from: file, contentType: "image/gif")
        #expect(metadata.dim == "37x61")
        #expect(metadata.blurhash != nil)
    }

    @Test func audioDoesNotRequireVisualMetadata() async throws {
        let file = try temporaryFile(Data("test audio bytes".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let metadata = try await BlossomPostMetadata().fillingMissingFields(from: file, contentType: "audio/mp4")
        #expect(metadata.hash != nil)
        #expect(metadata.dim == nil)
        #expect(metadata.blurhash == nil)
        #expect(!metadata.needsDownload(contentType: "audio/mp4"))
    }

    @Test func cancellationStopsMetadataDownload() async throws {
        let task = Task {
            try await BlossomPostMetadata().completing(from: URL(string: "https://example.com/image.png")!, contentType: "image/png") { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw URLError(.timedOut)
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled upload must not finish its metadata download")
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
        let metadata = try await BlossomPostMetadata().fillingMissingFields(from: file, contentType: "video/mp4")
        #expect(metadata.dim == "32x48")
        #expect(metadata.hash != nil)
        #expect(metadata.blurhash?.count == 28)
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
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
