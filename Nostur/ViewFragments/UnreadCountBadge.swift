//
//  UnreadCountBadge.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/08/2026.
//

import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    var background: Color = .red
    var foreground: Color = .white
    
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(foreground)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, count > 9 ? 4 : 5)
                .padding(.vertical, 2)
                .background(background)
                .clipShape(Capsule())
                .allowsHitTesting(false)
        }
    }
}

/// Used on the sidebar launcher and on account avatars inside the sidebar.
struct AccountNotificationBadge: View {
    @Environment(\.showSidebar) private var showSidebar
    @ObservedObject private var activeNotifications = NotificationsViewModel.shared
    @ObservedObject private var otherNotifications = OtherAccountNotifications.shared

    let pubkey: String
    var combinesAccounts = false
    var additionalUnread = 0

    var body: some View {
        if !combinesAccounts || !showSidebar.wrappedValue {
            UnreadCountBadge(count: count)
                .offset(x: 8, y: -4)
        }
    }

    private var count: Int {
        let activePubkey = AccountsState.shared.activeAccountPublicKey
        if combinesAccounts {
            return activeNotifications.unread(for: pubkey) +
                otherNotifications.total(excluding: pubkey) + additionalUnread
        }
        return pubkey == activePubkey
            ? activeNotifications.unread(for: pubkey)
            : otherNotifications.counts[pubkey, default: 0]
    }
}
