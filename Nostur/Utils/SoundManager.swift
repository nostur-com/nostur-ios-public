//
//  SoundManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2024.
//

import Foundation
import AVKit

class SoundManager {
    
    static let shared = SoundManager()
    
    private var player: AVAudioPlayer?
    
    public func playThunderzap() {
        guard SettingsStore.shared.thunderzapLevel != ThunderzapLevel.off.rawValue else { return }
        
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
        } 
        catch let error {
            L.og.error("Error: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        player?.stop()
    }
}
