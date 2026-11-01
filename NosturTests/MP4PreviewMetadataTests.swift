import Foundation
import Testing
@testable import Nostur

struct MP4PreviewMetadataTests {
    private func header(_ type: String, size: UInt64, extended: Bool = false) -> Data {
        func bytes(_ value: UInt64, count: Int) -> Data {
            Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        return bytes(extended ? 1 : size, count: 4) + Data(type.utf8)
            + (extended ? bytes(size, count: 8) : Data())
    }

    @Test func metadataJustLargerThanOldTailWindowIsFetchedWithoutMedia() async throws {
        // Layout of the reported 222MiB video. No large fixture or media download.
        let moovOffset = 231_575_431
        let moov = header("moov", size: 1_068_416) + Data(repeating: 42, count: 1_068_408)
        let front = header("ftyp", size: 32) + Data(repeating: 0, count: 24)
            + header("free", size: 8) + header("mdat", size: UInt64(moovOffset - 40))
        var requests: [Range<Int>] = []
        let result = try await MP4PreviewMetadata.load(fileSize: moovOffset + moov.count, frontData: front) { range in
            requests.append(range)
            #expect(range.lowerBound >= moovOffset)
            return moov.subdata(in: (range.lowerBound - moovOffset)..<(range.upperBound - moovOffset))
        }
        #expect(result?.offset == moovOffset)
        #expect(result?.data == moov)
        #expect(requests == [moovOffset..<(moovOffset + 8), (moovOffset + 8)..<(moovOffset + moov.count)])
    }

    @Test func reusesAlreadyDownloadedMetadataPrefix() async throws {
        let moov = header("moov", size: 100) + Data(repeating: 42, count: 92)
        let file = header("ftyp", size: 8) + moov
        var requests: [Range<Int>] = []
        let result = try await MP4PreviewMetadata.load(fileSize: file.count, frontData: Data(file.prefix(40))) { range in
            requests.append(range)
            return file.subdata(in: range)
        }
        #expect(result?.data == moov)
        #expect(requests == [40..<108])
    }

    @Test func extendedMediaSizeAndMetadataToEOF() async throws {
        let file = header("ftyp", size: 8) + header("mdat", size: 24, extended: true)
            + Data(repeating: 0, count: 8) + header("moov", size: 0) + Data(repeating: 42, count: 8)
        let result = try await MP4PreviewMetadata.load(fileSize: file.count, frontData: file) { _ in
            Issue.record("No request needed for a cached file")
            return Data()
        }
        #expect(result?.offset == 32)
        #expect(result?.data == file.subdata(in: 32..<48))
    }

    @Test func rejectsOversizedMetadataWithoutFetchingItsBody() async throws {
        let front = header("ftyp", size: 8) + header("moov", size: UInt64(MP4PreviewMetadata.maximumMetadataBytes + 1))
            + Data(repeating: 0, count: 8)
        let result = try await MP4PreviewMetadata.load(fileSize: MP4PreviewMetadata.maximumMetadataBytes + 9, frontData: front) { _ in
            Issue.record("Oversized metadata must not be downloaded")
            return Data()
        }
        #expect(result == nil)
    }

    @Test func rejectsTruncatedOverflowingAndNonMP4Boxes() async throws {
        for file in [header("ftyp", size: 7), header("ftyp", size: UInt64.max, extended: true),
                     header("ftyp", size: 1), header("junk", size: 8) + header("moov", size: 8)] {
            let result = try await MP4PreviewMetadata.load(fileSize: file.count, frontData: file) { _ in Data() }
            #expect(result == nil)
        }
    }

    @Test func boxWalkIsBounded() async throws {
        var file = header("ftyp", size: 8)
        for _ in 0..<MP4PreviewMetadata.maximumBoxes { file.append(header("free", size: 8)) }
        file.append(header("moov", size: 8))
        let result = try await MP4PreviewMetadata.load(fileSize: file.count, frontData: file) { _ in Data() }
        #expect(result == nil)
    }

    @Test func cancellationStopsBeforeFetching() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MP4PreviewMetadata.load(fileSize: 100, frontData: Data()) { _ in
                Issue.record("Cancelled preview must not fetch")
                return Data()
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
