//
//  ExpiryCountdownLabel.swift
//  Nostur
//
//  Live "{n}d left" countdown shown on an expiring (NIP-40) DM bubble.
//  Ticks on the app's shared minute timer (agoShouldUpdateSubject). Day/hour/minute
//  resolution is all we render, so a per-second timer isn't needed.
//

import SwiftUI

struct ExpiryCountdownLabel: View {
    let expiresAt: Int

    @Environment(\.theme) private var theme
    @State private var label: String = ""

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock")
            Text(label)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.accent)
        .onAppear { recompute() }
        .onReceive(AppState.shared.agoShouldUpdateSubject) { _ in recompute() }
    }

    private func recompute() {
        let next = DMExpiry.countdownLabel(expiresAt: expiresAt, now: Int(Date.now.timeIntervalSince1970))
        if next != label { label = next }
    }
}
