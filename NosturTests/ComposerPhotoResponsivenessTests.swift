import Foundation
import Testing
import UIKit
@testable import Nostur

@MainActor
@Suite(.serialized)
struct ComposerPhotoResponsivenessTests {
    private func photoData() async throws -> Data {
        try await Task.detached {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 3072), format: format)
            let image = renderer.image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4096, height: 3072))
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 400, y: 300, width: 2000, height: 1800))
            }
            return try #require(image.jpegData(compressionQuality: 0.95))
        }.value
    }

    @Test("Seven-photo preparation leaves the main actor responsive", arguments: [false, true])
    func prepareSevenPhotos(useNip96: Bool) async throws {
        let data = try await photoData()
        let images = (0..<7).map {
            PostedImageMeta(index: $0, data: data, type: .jpeg, uniqueId: "photo-\($0)")
        }
        let model = TypingTextModel()
        let method: UploadMethod = useNip96 ? .nip96(URL(string: "https://example.com/upload")!) : .blossom
        var ticks: [Date] = []
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                ticks.append(Date())
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        defer { heartbeat.cancel() }
        await Task.yield()
        let prepared = await prepareUploadItems(
            pubkey: String(repeating: "a", count: 64), images: images,
            typingTextModel: model, uploadMethod: method
        )
        ticks.append(Date())

        #expect(prepared.count == 7)
        #expect(prepared.map { $0.3 } == Array(0..<7))
        #expect(prepared.allSatisfy { $0.1 == "image/jpeg" && $0.2 != nil })
        #expect(UIImage(data: try #require(prepared.first).0)?.size.width == 2800)
        #expect(ticks.count > 2, "UI work must run while photos are being prepared")
        let longestGap = zip(ticks, ticks.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0
        #expect(longestGap < 0.5, "Main actor stalled for \(longestGap) seconds")
    }

    @Test("Photo previews are decoded at a bounded size")
    func previewThumbnail() async throws {
        let thumbnail = try #require(await prepareComposerPhotoPreview(data: try await photoData()))
        #expect(thumbnail.size == CGSize(width: 1600, height: 1200))
        #expect(thumbnail.cgImage != nil)
        #expect(await prepareComposerPhotoPreview(data: Data()) == nil)
    }
}
