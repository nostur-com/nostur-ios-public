//
//  BuildIdentity.swift
//  Nostur
//
//  Gives locally installed test builds a visible identity. The Mach-O UUID is
//  regenerated whenever the app is linked, so it distinguishes two binaries
//  even when their marketing version and CI build number are unchanged.
//

import Foundation

let TEST_BUILD_ID = BuildIdentity.current

private enum BuildIdentity {
    static let current: String = {
        let bundle = Bundle.main
        let debugDylib = bundle.bundleURL.appendingPathComponent("Nostur.debug.dylib")
        let binaryURL = FileManager.default.fileExists(atPath: debugDylib.path)
            ? debugDylib
            : bundle.executableURL

        guard let binaryURL else { return "unknown" }
        if let uuid = machOUUID(at: binaryURL) {
            return String(uuid.prefix(8))
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binaryURL.path),
              let modified = attributes[.modificationDate] as? Date
        else { return "unknown" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss"
        return formatter.string(from: modified)
    }()

    private static func machOUUID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let magic = uint32(in: data, at: 0)
        else { return nil }

        let headerSize: Int
        switch magic {
        case 0xfeedfacf: // MH_MAGIC_64
            headerSize = 32
        case 0xfeedface: // MH_MAGIC
            headerSize = 28
        default:
            return nil
        }

        guard let commandCount = uint32(in: data, at: 16) else { return nil }
        var offset = headerSize
        for _ in 0..<commandCount {
            guard let command = uint32(in: data, at: offset),
                  let commandSize = uint32(in: data, at: offset + 4),
                  commandSize >= 8,
                  offset + Int(commandSize) <= data.count
            else { return nil }

            if command == 0x1b, offset + 24 <= data.count { // LC_UUID
                return data[(offset + 8)..<(offset + 24)]
                    .map { String(format: "%02x", $0) }
                    .joined()
            }
            offset += Int(commandSize)
        }
        return nil
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
