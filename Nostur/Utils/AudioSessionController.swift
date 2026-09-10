import AVFoundation
import Foundation

/// All app-owned session mutations run in order off the main thread. Playback and
/// recording await completion; UI state and ownership stay on the main actor.
@MainActor
final class AudioSessionController {
    enum Profile: Equatable {
        case mixedPlayback, playback, recording, effect
    }

    enum Operation: Equatable {
        case configure(Profile), activateCurrent, deactivate
    }

    enum SessionError: Error {
        case recordingInProgress
    }

    static let shared = AudioSessionController()

    private let queue = DispatchQueue(label: "com.nostur.audioSession", qos: .userInitiated)
    private let operation: (Operation) throws -> Void
    private var owner: UUID?
    private var profile: Profile?
    private var effects = Set<UUID>()

    // Injectable session work lets tests hold activation without using audio hardware.
    init(operation: @escaping (Operation) throws -> Void = AudioSessionController.apply) {
        self.operation = operation
    }

    func prepare(_ profile: Profile, owner: UUID) async throws {
        try Task.checkCancellation()
        if self.profile == .recording, self.owner != owner {
            throw SessionError.recordingInProgress
        }
        self.owner = owner
        self.profile = profile
        do {
            try await perform(.configure(profile))
            try Task.checkCancellation()
            guard self.owner == owner else { throw CancellationError() }
        } catch {
            // The cancelling caller releases its request. In particular, a recorder
            // must retain ownership until its queued deactivation has been submitted.
            if !(error is CancellationError) { abandon(owner: owner) }
            throw error
        }
    }

    func prepareDefaultPlayback() async throws {
        // Foreground/appearance work must not overwrite media or recording setup.
        guard owner == nil else { return }
        let owner = UUID()
        try await prepare(.mixedPlayback, owner: owner)
        abandon(owner: owner)
    }

    func prepareEffect(owner: UUID) async throws {
        try Task.checkCancellation()
        effects.insert(owner)
        do {
            if profile == .playback || profile == .recording {
                // A short effect shares ongoing media/recording without changing its category.
                try await perform(.activateCurrent)
                try Task.checkCancellation()
            } else {
                try await prepare(.effect, owner: owner)
            }
        } catch {
            effects.remove(owner)
            throw error
        }
    }

    func abandon(owner: UUID) {
        effects.remove(owner)
        guard self.owner == owner else { return }
        self.owner = nil
        profile = nil
    }

    func deactivate(owner: UUID) async throws {
        // A delayed recording completion must not deactivate a newer audio user.
        guard self.owner == owner else { return }
        abandon(owner: owner)
        // A sound already queued or playing still needs the session. Leave it active
        // just as normal effect playback does; the next media request sets its category.
        guard effects.isEmpty else { return }
        try await perform(.deactivate)
    }

    private func perform(_ request: Operation) async throws {
        let operation = self.operation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try operation(request)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func apply(_ operation: Operation) throws {
        let session = AVAudioSession.sharedInstance()
        switch operation {
        case .configure(let profile):
            let category: AVAudioSession.Category
            let options: AVAudioSession.CategoryOptions
            switch profile {
            case .mixedPlayback:
                category = .playback
                options = [.mixWithOthers]
            case .playback:
                category = .playback
                options = []
            case .effect:
                category = .ambient
                options = [.mixWithOthers]
            case .recording:
                category = .playAndRecord
#if targetEnvironment(macCatalyst)
                options = [.allowBluetooth, .allowBluetoothA2DP]
#else
                options = [.defaultToSpeaker]
#endif
            }
            if session.category != category || session.mode != .default || session.categoryOptions != options {
                try session.setCategory(category, mode: .default, options: options)
            }
            // AVAudioSession has no public isActive getter. Do not cache activation:
            // interruptions, capture sessions and LiveKit can change it independently.
            try session.setActive(true)
        case .activateCurrent:
            try session.setActive(true)
        case .deactivate:
            try session.setActive(false)
        }
    }
}
