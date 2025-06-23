//
//  SoundManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2024.
//

import Foundation
import AVKit
import AVFoundation

class SoundManager {
    
    static let shared = SoundManager()
    
    private var player: AVAudioPlayer?
    
    public func playThunderzap() {
        guard SettingsStore.shared.thunderzapLevel != ThunderzapLevel.off.rawValue else { return }
        
        // Configure audio session to mix with other audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            L.og.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        
        let thunderzapFile = if SettingsStore.shared.thunderzapLevel == ThunderzapLevel.low.rawValue {
            "Thunderzap16"
        }
        else {
            "Thunderzap71"
        }
        guard let url = Bundle.main.url(forResource: thunderzapFile, withExtension: ".m4a") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            
            
            // Need to restore for media control center
            // but only if our app was playing, else it will stop music/podcast from other apps
            if AnyPlayerModel.shared.isPlaying {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            }
        }
        catch let error {
            L.og.error("Error: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        player?.stop()
    }
}
