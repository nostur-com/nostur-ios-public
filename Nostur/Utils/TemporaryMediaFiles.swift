import Foundation

/// Media drafts are kept in memory, so files from an earlier app session are
/// abandoned. Never sweep the current session: it may contain an unfinished
/// recording, an upload, a share export, or a video still being played.
final class TemporaryMediaFiles {
    static let shared = TemporaryMediaFiles()

    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let cachesDirectory: URL
    private let sessionStartedAt: Date
    let sessionDirectory: URL

    init(fileManager: FileManager = .default,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         cachesDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!,
         sessionId: UUID = UUID(), sessionStartedAt: Date = .now) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
        self.cachesDirectory = cachesDirectory
        self.sessionStartedAt = sessionStartedAt
        self.sessionDirectory = temporaryDirectory
            .appendingPathComponent("NosturTemporaryMedia", isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)
    }

    func directory(named name: String) -> URL {
        let directory = sessionDirectory.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func makeURL(extension fileExtension: String) -> URL {
        directory(named: "media").appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    /// Run off the main thread. Only known app-owned paths are eligible;
    /// UIKit/provider temporary files and persistent DM downloads are untouched.
    func cleanUpAbandonedFiles() {
        let sessions = sessionDirectory.deletingLastPathComponent()
        for url in contents(of: sessions) where url.lastPathComponent != sessionDirectory.lastPathComponent {
            guard UUID(uuidString: url.lastPathComponent) != nil,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            remove(url)
        }

        // Migration for versions that wrote directly into tmp or Caches.
        // Give legacy files a two-hour grace period. New writers use this session.
        let cutoff = sessionStartedAt.addingTimeInterval(-2 * 60 * 60)
        for url in contents(of: temporaryDirectory) where Self.isLegacyMediaFile(url) {
            removeIfOlder(url, than: cutoff)
        }
        for directory in [temporaryDirectory.appendingPathComponent("dm-attachments"),
                          cachesDirectory.appendingPathComponent("a0-own-recordings"),
                          cachesDirectory.appendingPathComponent("a0")] {
            for url in contents(of: directory) {
                removeIfOlder(url, than: cutoff)
            }
            // Only remove empty directories, never an unrecognized nested folder.
            if let remaining = try? fileManager.contentsOfDirectory(atPath: directory.path), remaining.isEmpty {
                remove(directory)
            }
        }
    }

    private static func isLegacyMediaFile(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        if name == "temp_gif", ext == "gif" { return true }
        if name == "dm_file" { return true } // Old QuickLook DM preview.
        if name.hasPrefix("nostur_shared_"), UUID(uuidString: String(name.dropFirst("nostur_shared_".count))) != nil {
            return ["mp4", "gif"].contains(ext)
        }
        return UUID(uuidString: name) != nil && ["mp4", "mov", "m4v", "webm"].contains(ext)
    }

    private func contents(of directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    private func removeIfOlder(_ url: URL, than cutoff: Date) {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .creationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let date = values.contentModificationDate ?? values.creationDate, date < cutoff else { return }
        remove(url)
    }

    private func remove(_ url: URL) {
        do { try fileManager.removeItem(at: url) }
        catch { L.maintenance.error("Could not remove abandoned media: \(url.lastPathComponent): \(error.localizedDescription)") }
    }
}
