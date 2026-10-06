import XCTest
import ImageIO
import UniformTypeIdentifiers
import Nuke
@testable import Nostur

final class ProfileImageSafetyTests: XCTestCase {
    func testRejectsInvalidAnimatedImageData() {
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(Data("not an image".utf8), policy: .profilePicture))
    }

    @MainActor
    func testUnreadableDataIsNotReportedAsOversized() {
        let data = Data("not an image".utf8)
        let decoder = LimitedImageDecoder(underlying: ImageDecoders.Default(), policy: .post)
        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case .unreadableImage? = error as? LimitedImageDecoder.Error else {
                return XCTFail("Unreadable image metadata must not be classified as oversized")
            }
            guard case .error? = MediaViewVM.sizeFailureState(for: error, loadAnyway: false) else {
                return XCTFail("Unreadable data should show a read error instead of a size error")
            }
        }
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

    func testPostPipelineAcceptsGIFWithReportedDimensions() async throws {
        // Regression: the Hivetalk GIF has 340 frames at 850 x 1080, exceeding
        // both the old 300-frame cap and the old 250-million-pixel cap.
        let data = try makeGIF(width: 850, height: 1080, frameCount: 340)
        XCTAssertTrue(ProfileImageSafety.isSafeAnimatedImage(data, policy: .post))
        XCTAssertTrue(ProfileImageSafety.isSafeAnimatedImage(data, policy: .postLoadAnyway))
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: .profilePicture))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).gif")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let response = try await ImageProcessing.shared.content.imageTask(with: ImageRequest(url: url)).response
        XCTAssertEqual(response.container.type, .gif)
        XCTAssertEqual(response.container.data, data)
        XCTAssertEqual(response.image.size.width, 850)
        XCTAssertEqual(response.image.size.height, 1080)
    }

    func testLargerAnimationOffersWorkingOverride() async throws {
        let data = try makeGIF(width: 2, height: 2, frameCount: 401)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).gif")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await ImageProcessing.shared.content.imageTask(with: ImageRequest(url: url)).response
            XCTFail("Automatic loading must explain the animation limit")
        }
        catch {
            let state = await MediaViewVM.sizeFailureState(for: error, loadAnyway: false)
            XCTAssertEqual(state, .animationTooLarge)
        }

        let response = try await ImageProcessing.shared.contentLoadAnyway.imageTask(with: ImageRequest(url: url)).response
        XCTAssertEqual(response.container.type, .gif)
        XCTAssertEqual(response.container.data, data)
    }

    func testPostStillRejectsExcessiveFrameCount() throws {
        let data = try makeGIF(width: 2, height: 2, frameCount: 601)
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: .post))
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: .postLoadAnyway))
    }

    @MainActor
    func testSizeFailuresOfferOverrideOnlyBelowHardLimits() {
        XCTAssertEqual(MediaViewVM.sizeFailureState(for: LimitedImageDecoder.Error.animationTooLarge, loadAnyway: false), .animationTooLarge)
        XCTAssertEqual(MediaViewVM.sizeFailureState(for: LimitedImageDecoder.Error.animationTooLarge, loadAnyway: true), .mediaExceedsSafetyLimit)
        XCTAssertEqual(MediaViewVM.sizeFailureState(for: LimitedImageDecoder.Error.unsafeImageDimensions, loadAnyway: false), .mediaExceedsSafetyLimit)
        let downloadError = LimitedDataLoader.Error.responseTooLarge(limit: 50 * 1_048_576)
        XCTAssertEqual(MediaViewVM.sizeFailureState(for: downloadError, loadAnyway: false), .imageTooLarge)
        XCTAssertEqual(MediaViewVM.sizeFailureState(for: downloadError, loadAnyway: true), .mediaExceedsSafetyLimit)
    }

    func testRejectsExcessiveTotalAnimationPixels() throws {
        let data = try makeGIF(width: 10, height: 10, frameCount: 3)
        let policy = ProfileImageSafety.Policy(
            maximumDimension: 100,
            maximumPixelCount: 10_000,
            maximumAnimatedFrameCount: 10,
            maximumAnimatedPixelCount: 250
        )
        XCTAssertFalse(ProfileImageSafety.isSafeAnimatedImage(data, policy: policy))
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
