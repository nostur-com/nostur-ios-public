//
//  NXDelayur.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import Foundation

// Helper to debounce .resumeProcessing() on every haltedProcesssing = true
class NXDelayur {
    
    private var delayurTimer: Timer?
    private var delaying: Bool = false
    private var onResume: (() ->())?

    func setDelayur(_ isDelaying: Bool, seconds: TimeInterval? = nil, onResume: (() ->())? = nil) {
        self.delaying = isDelaying // Data race Write of size 1 by thread 1
        self.onResume = onResume
        if delaying, let seconds {
            restartDelayurTimer(timeInterval: seconds)
        }
        else if !isDelaying {
            delayurTimer?.invalidate()
        }
    }
    
    public var isDelaying: Bool { delaying } // Data race in Nostur.NXDelayur.isDelaying.getter : Swift.Bool at 0x144288fe0 (Thread 87)

    private func restartDelayurTimer(timeInterval ti: TimeInterval) {
        delayurTimer?.invalidate()
        delayurTimer = Timer.scheduledTimer(timeInterval: ti, target: self, selector: #selector(delayurTimerFired), userInfo: nil, repeats: false)
    }

    @objc private func delayurTimerFired() {
        DispatchQueue.main.async { [weak self] in
            self?.delaying = false
            self?.onResume?()
        }
    }
}
