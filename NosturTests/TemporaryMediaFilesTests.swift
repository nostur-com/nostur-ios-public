import Foundation
import Testing
@testable import Nostur

@Suite("Temporary media cleanup")
struct TemporaryMediaFilesTests {
    @Test("Sweeps previous sessions while preserving current media and unrelated files")
    func preservesCurrentSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let temporary = root.appendingPathComponent("tmp")
        let caches = root.appendingPathComponent("Caches")
        let files = TemporaryMediaFiles(temporaryDirectory: temporary, cachesDirectory: caches)
        let currentVideo = files.makeURL(extension: "mp4")
        try Data([1]).write(to: currentVideo)
        let sessions = files.sessionDirectory.deletingLastPathComponent()
        let abandoned = sessions.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data([2]).write(to: abandoned.appendingPathComponent("unfinished.m4a"))
        let unrelated = sessions.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let dmFiles = caches.appendingPathComponent("DMFiles")
        try FileManager.default.createDirectory(at: dmFiles, withIntermediateDirectories: true)
        let keptDM = dmFiles.appendingPathComponent("attachment.mp4")
        try Data([3]).write(to: keptDM)

        files.cleanUpAbandonedFiles()
        files.cleanUpAbandonedFiles() // Repeated maintenance is safe.

        #expect(FileManager.default.fileExists(atPath: currentVideo.path))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: keptDM.path))
    }

    @Test("Removes old legacy media, recordings, and audio conversions with a grace period")
    func cleansLegacyMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let temporary = root.appendingPathComponent("tmp")
        let caches = root.appendingPathComponent("Caches")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let now = Date.now
        let files = TemporaryMediaFiles(temporaryDirectory: temporary, cachesDirectory: caches, sessionStartedAt: now)
        let oldNames = ["\(UUID().uuidString).mp4", "\(UUID().uuidString).mov", "nostur_shared_\(UUID().uuidString).gif", "temp_gif.gif", "dm_file.pdf"]
        var oldFiles = oldNames.map { temporary.appendingPathComponent($0) }
        for folder in ["a0", "a0-own-recordings"] {
            let directory = caches.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            oldFiles.append(directory.appendingPathComponent("\(UUID().uuidString).m4a"))
        }
        let attachments = temporary.appendingPathComponent("dm-attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        oldFiles.append(attachments.appendingPathComponent("attachment.pdf"))
        for url in oldFiles {
            try Data([1]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 60 * 60)], ofItemAtPath: url.path)
        }
        let recent = temporary.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data([2]).write(to: recent)
        let unrelated = temporary.appendingPathComponent("provider-video.mp4")
        try Data([3]).write(to: unrelated)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3 * 60 * 60)], ofItemAtPath: unrelated.path)
        let symlink = temporary.appendingPathComponent("\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: unrelated)

        files.cleanUpAbandonedFiles()

        for url in oldFiles { #expect(!FileManager.default.fileExists(atPath: url.path)) }
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: symlink.path))
    }
}
