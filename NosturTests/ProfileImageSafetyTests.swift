import XCTest
import ImageIO
import UniformTypeIdentifiers
import Nuke
@testable import Nostur

final class ProfileImageSafetyTests: XCTestCase {
    func testRejectsInvalidAnimatedImageData() {
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(Data("not an image".utf8), policy: .profilePicture))
    }

    func testAcceptsSmallGIF() throws {
        let data = try makeGIF(width: 2, height: 2)
        XCTAssertTrue(ProfileImageSafety.isSafeAnimatedImage(data, policy: .profilePicture))
    }

    func testRejectsOversizedGIFDimensions() throws {
        let data = try makeGIF(width: ProfileImageSafety.Policy.profilePicture.maximumDimension + 1, height: 1)
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: .profilePicture))
    }

    func testRejectsTooManyAnimationFrames() throws {
        let data = try makeGIF(width: 2, height: 2, frameCount: 2)
        let oneFramePolicy = ProfileImageSafety.Policy(
            maximumDimension: 100,
            maximumPixelCount: 10_000,
            maximumAnimatedFrameCount: 1,
            maximumAnimatedPixelCount: 10_000
        )
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: oneFramePolicy))
    }

    func testLimitedDataLoaderRejectsDeclaredSize() {
        let response = URLResponse(
            url: URL(string: "https://example.com/image.gif")!,
            mimeType: "image/gif",
            expectedContentLength: 101,
            textEncodingName: nil
        )
        let source = StubDataLoader(response: response, chunks: [Data(count: 1)])
        let loader = LimitedDataLoader(underlying: source, byteLimit: 100)
        var receivedBytes = 0
        var receivedError: Swift.Error?

        _ = loader.loadData(with: URLRequest(url: response.url!)) { data, _ in
            receivedBytes += data.count
        } completion: { error in
            receivedError = error
        }

        XCTAssertEqual(receivedBytes, 0)
        XCTAssertTrue(receivedError is LimitedDataLoader.Error)
        XCTAssertTrue(source.cancellable.isCancelled)
    }

    func testLimitedDataLoaderRejectsActualStreamedSize() {
        let response = URLResponse(
            url: URL(string: "https://example.com/image.gif")!,
            mimeType: "image/gif",
            expectedContentLength: -1,
            textEncodingName: nil
        )
        let source = StubDataLoader(response: response, chunks: [Data(count: 60), Data(count: 41)])
        let loader = LimitedDataLoader(underlying: source, byteLimit: 100)
        var receivedBytes = 0
        var receivedError: Swift.Error?

        _ = loader.loadData(with: URLRequest(url: response.url!)) { data, _ in
            receivedBytes += data.count
        } completion: { error in
            receivedError = error
        }

        XCTAssertEqual(receivedBytes, 60)
        XCTAssertTrue(receivedError is LimitedDataLoader.Error)
        XCTAssertTrue(source.cancellable.isCancelled)
    }

    private func makeGIF(width: Int, height: Int, frameCount: Int = 1) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ))
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1,
                kCGImagePropertyGIFUnclampedDelayTime: 0.1
            ]
        ]
        for frameIndex in 0..<frameCount {
            context.setFillColor(CGColor(
                red: CGFloat(frameIndex % 3) / 2,
                green: CGFloat((frameIndex + 1) % 3) / 2,
                blue: CGFloat((frameIndex + 2) % 3) / 2,
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class StubCancellable: Cancellable, @unchecked Sendable {
    var isCancelled = false
    func cancel() {
        isCancelled = true
    }
}

private final class StubDataLoader: DataLoading, @unchecked Sendable {
    let response: URLResponse
    let chunks: [Data]
    let cancellable = StubCancellable()

    init(response: URLResponse, chunks: [Data]) {
        self.response = response
        self.chunks = chunks
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping (Data, URLResponse) -> Void,
        completion: @escaping (Swift.Error?) -> Void
    ) -> any Cancellable {
        for chunk in chunks {
            didReceiveData(chunk, response)
        }
        completion(nil)
        return cancellable
    }
}
