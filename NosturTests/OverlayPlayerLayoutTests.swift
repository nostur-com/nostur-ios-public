import CoreData
import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class OverlayPlayerLayoutTests: XCTestCase {
    func testDownloadControlFollowsChangingAsymmetricSafeArea() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let vm = AnyPlayerModel.shared
        vm.close()
        vm.isShown = true
        vm.isLoading = true
        vm.isStream = false
        vm.didFinishPlaying = true
        vm.viewMode = .fullscreen
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        let entity = try XCTUnwrap(DataProvider.shared().container.managedObjectModel.entitiesByName["CloudAccount"])
        let account = CloudAccount(entity: entity, insertInto: context)
        account.publicKey = String(repeating: "a", count: 64)
        let loggedInAccount = LoggedInAccount(account)
        let host = UIHostingController(rootView: OverlayPlayer(vm: vm)
            .environmentObject(loggedInAccount)
            .background { Color.black.ignoresSafeArea() }
            .environment(\.theme, Theme(accent: .red)))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            vm.close()
            window.isHidden = true
        }

        let originalSize = window.bounds.size
        // Move the obstruction without changing the window size, as a Duo pose can.
        for insets in [UIEdgeInsets(top: 40, left: 0, bottom: 0, right: 100),
                       UIEdgeInsets(top: 100, left: 70, bottom: 0, right: 35)] {
            host.additionalSafeAreaInsets = insets
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            window.layoutIfNeeded()
            XCTAssertEqual(window.bounds.size, originalSize)
            let safeFrame = host.view.safeAreaLayoutGuide.layoutFrame
            let downloadFrame = CGRect(x: safeFrame.maxX - 44, y: safeFrame.minY + 8, width: 32, height: 32)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Video controls with safe area \(insets)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(try whitePixelCount(image, in: downloadFrame), 15,
                                 "Download icon must remain inside the current safe area")
            let obstructedTrailingFrame = CGRect(x: safeFrame.maxX, y: 0,
                                                width: window.bounds.maxX - safeFrame.maxX,
                                                height: safeFrame.minY + 50)
            XCTAssertEqual(try whitePixelCount(image, in: obstructedTrailingFrame), 0,
                           "No top controls should extend into the camera's unsafe region")
        }
    }

    private func whitePixelCount(_ image: UIImage, in rect: CGRect) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                    CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            var count = 0
            for y in max(0, Int(rect.minY))..<min(height, Int(rect.maxY)) {
                for x in max(0, Int(rect.minX))..<min(width, Int(rect.maxX)) {
                    let i = (y * width + x) * 4
                    if data[i] > 220 && data[i + 1] > 220 && data[i + 2] > 220 { count += 1 }
                }
            }
            return count
        }
    }
}
