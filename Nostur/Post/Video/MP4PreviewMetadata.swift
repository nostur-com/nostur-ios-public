import Foundation

/// Walks top-level MP4 boxes without downloading their media payloads.
enum MP4PreviewMetadata {
    static let maximumMetadataBytes = 4_194_304
    static let maximumBoxes = 32

    struct LocatedData {
        let offset: Int
        let data: Data
    }

    static func load(
        fileSize: Int,
        frontData: Data,
        fetch: (Range<Int>) async throws -> Data
    ) async throws -> LocatedData? {
        guard fileSize >= 8 else { return nil }
        func readHeader(at offset: Int, count: Int) async throws -> Data {
            let range = offset..<(offset + count)
            if range.upperBound <= frontData.count { return frontData.subdata(in: range) }
            return try await fetch(range)
        }
        var offset = 0
        for _ in 0..<maximumBoxes {
            try Task.checkCancellation()
            guard offset <= fileSize - 8 else { return nil }
            var header = try await readHeader(at: offset, count: 8)
            guard header.count == 8 else { return nil }

            let shortSize = integer(header, range: 0..<4)
            let headerSize = shortSize == 1 ? 16 : 8
            let size: UInt64
            switch shortSize {
            case 0: size = UInt64(fileSize - offset)
            case 1:
                guard fileSize - offset >= 16 else { return nil }
                header.append(try await readHeader(at: offset + 8, count: 8))
                guard header.count == 16 else { return nil }
                size = integer(header, range: 8..<16)
            default: size = shortSize
            }
            // Check before converting or adding: box sizes are untrusted 64-bit values.
            guard size >= UInt64(headerSize), size <= UInt64(fileSize - offset) else { return nil }
            let end = offset + Int(size)
            if header.subdata(in: 4..<8) == Data("moov".utf8) {
                guard size <= UInt64(maximumMetadataBytes) else { return nil }
                var data: Data
                if offset < frontData.count {
                    data = frontData.subdata(in: offset..<min(end, frontData.count))
                } else {
                    data = Data(header.prefix(Int(size)))
                }
                if offset + data.count < end {
                    let missingRange = (offset + data.count)..<end
                    let missing = try await fetch(missingRange)
                    guard missing.count == missingRange.count else { return nil }
                    data.append(missing)
                }
                return LocatedData(offset: offset, data: data)
            }
            // Require an MP4 signature before following arbitrary offsets in other formats.
            if offset == 0 && header.subdata(in: 4..<8) != Data("ftyp".utf8) { return nil }
            offset = end
        }
        return nil
    }

    private static func integer(_ data: Data, range: Range<Int>) -> UInt64 {
        range.reduce(0) { ($0 << 8) | UInt64(data[$1]) }
    }
}

/// Enforces the requested byte limit even when a server ignores Range.
enum VideoPreviewRangeLoader {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    static func fetch(url: URL, range: Range<Int>, session: URLSession? = nil) async throws -> Data {
        guard !range.isEmpty, range.lowerBound >= 0 else { throw URLError(.badURL) }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (bytes, response) = try await (session ?? self.session).bytes(for: request)
        // Cancel the underlying transfer when rejecting headers or an oversized body.
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 206 {
            guard response.value(forHTTPHeaderField: "Content-Range")?
                .hasPrefix("bytes \(range.lowerBound)-\(range.upperBound - 1)/") == true else {
                throw URLError(.badServerResponse)
            }
        } else if response.statusCode != 200 || range.lowerBound != 0 {
            throw URLError(.badServerResponse)
        }
        guard response.expectedContentLength <= Int64(range.count) else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        data.reserveCapacity(range.count)
        for try await byte in bytes {
            guard data.count < range.count else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        // A server may return a complete small file with 200 when size probing
        // was unavailable. It is safe to use that body at offset zero.
        guard response.statusCode == 200 || data.count == range.count else { throw URLError(.badServerResponse) }
        return data
    }
}
