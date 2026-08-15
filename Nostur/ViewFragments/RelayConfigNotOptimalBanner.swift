//
//  RelayConfigNotOptimalBanner.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2026.
//

import SwiftUI

struct RelayConfigNotOptimalBanner: View {
    enum Style {
        case compact
        case detail
    }
    
    var style: Style = .compact
    /// Relays sheet opened from the notification keeps showing after optimize so the user sees "looks good".
    var showsWhenGood: Bool = false
    
    @Environment(\.theme) private var theme
    @AppStorage(RelayConfigHealth.snoozedUntilKey) private var snoozedUntilTimestamp: Double = 0
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "read == YES")
    )
    private var readRelays: FetchedResults<CloudRelay>
    
    private var receiveCount: Int { readRelays.count }
    
    private var isNotOptimal: Bool {
        !RelayConfigHealth.looksGood(receiveCount: receiveCount)
    }
    
    private var isSnoozed: Bool {
        snoozedUntilTimestamp > Date.now.timeIntervalSince1970
    }
    
    private var shouldShow: Bool {
        switch style {
        case .compact:
            return RelayConfigHealth.shouldShowCompactBanner(receiveCount: receiveCount, isSnoozed: isSnoozed)
        case .detail:
            return RelayConfigHealth.shouldShowDetailBanner(isNotOptimal: isNotOptimal, showsWhenGood: showsWhenGood)
        }
    }
    
    private var statusTitle: String {
        switch (style, isNotOptimal) {
        case (.compact, true):
            String(localized: "Relay configuration looks not optimal")
        case (.compact, false):
            String(localized: "Relay configuration looks good")
        case (.detail, true):
            String(localized: "Configuration looks not optimal")
        case (.detail, false):
            String(localized: "Configuration looks good")
        }
    }
    
    private var receiveCountText: String {
        String(localized: "(\(receiveCount) receive relays)")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if shouldShow {
                Group {
                    if style == .compact {
                        compactRow
                    }
                    else {
                        detailBlock
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, style == .compact ? 10 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.secondaryBackground)
                .animation(.easeInOut(duration: 0.2), value: isNotOptimal)
            }
        }
    }

    private var statusIcon: some View {
        Image(systemName: isNotOptimal ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.body)
            .foregroundColor(isNotOptimal ? .orange : .green)
            .accessibilityHidden(true)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.footnote)
                        .foregroundColor(theme.primary)
                    Text(receiveCountText)
                        .font(.footnote)
                        .foregroundColor(theme.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                AppSheetsModel.shared.showRelaysFromNotification = true
            }
            
            Button {
                RelayConfigHealth.snooze()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide"))
        }
    }

    private var detailBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline)
                        .foregroundColor(theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(receiveCountText)
                        .font(.subheadline)
                        .foregroundColor(theme.primary)
                        .lineLimit(1)
                }
                if isNotOptimal {
                    (Text("Recommendation: reduce receive relays to \(RelayConfigHealth.recommendedReceiveRelayMin)–\(RelayConfigHealth.recommendedReceiveRelayMax) max (tap on the ")
                     + Text(Image(systemName: "arrow.down.circle.fill")).foregroundColor(.green)
                     + Text(" to toggle)"))
                        .font(.footnote)
                        .foregroundColor(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
