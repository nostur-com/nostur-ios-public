//
//  SoundManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2024.
//

import Foundation
import AVKit
import AVFoundation

@MainActor
class SoundManager: NSObject, AVAudioPlayerDelegate {
    
    static let shared = SoundManager()
    
    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var playbackRequest: UUID?
    
    public func playThunderzap() {
        guard SettingsStore.shared.thunderzapLevel != ThunderzapLevel.off.rawValue else { return }
        
        stop()
        let thunderzapFile = if SettingsStore.shared.thunderzapLevel == ThunderzapLevel.low.rawValue {
            "Thunderzap16"
        }
        else {
            "Thunderzap71"
        }
        guard let url = Bundle.main.url(forResource: thunderzapFile, withExtension: ".m4a") else { return }
        let request = UUID()
        playbackRequest = request
        playbackTask = Task { @MainActor in
            do {
                try await AudioSessionController.shared.prepareEffect(owner: request)
                try Task.checkCancellation()
                guard playbackRequest == request else { return }
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                if player?.play() != true {
                    AudioSessionController.shared.abandon(owner: request)
                }
                playbackTask = nil
            } catch {
                guard playbackRequest == request else { return }
                AudioSessionController.shared.abandon(owner: request)
                playbackTask = nil
                if !(error is CancellationError) {
                    L.og.error("Failed to play thunderzap: \(error.localizedDescription)")
                }
            }
        }
    }
    public func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        if let playbackRequest {
            AudioSessionController.shared.abandon(owner: playbackRequest)
        }
        playbackRequest = nil
        player?.stop()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }
}
