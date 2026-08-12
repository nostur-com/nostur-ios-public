//
//  MediaFeedSourceSettings.swift
//  Nostur
//

import SwiftUI

struct MediaFeedSourceSettings: View {
    @ObservedObject var feed: CloudFeed
    @ObservedObject var draft: FeedSettingsDraft
    @ObservedObject private var settings = SettingsStore.shared

    private var selectedRelayCount: Int {
        draft.selectedRelayCount
    }

    var body: some View {
        Section("Show content from") {
            sourceRow(
                .follows,
                title: String(localized: "People I follow"),
                description: String(localized: "Only posts from people you follow")
            )

            sourceRow(
                .webOfTrust,
                title: String(localized: "My web of trust"),
                description: String(localized: "Posts from your follows and their follows")
            )
            .disabled(settings.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue)

            sourceRow(
                .selectedRelays,
                title: String(localized: "Everyone on selected relays"),
                description: selectedRelayCount == 0
                    ? String(localized: "Select at least one relay first")
                    : String(localized: "Includes people outside your web of trust")
            )
            .disabled(selectedRelayCount == 0)
        }

        Section {
            NavigationLink(destination: FeedRelaysPicker(selectedRelays: $draft.mediaRelays)) {
                HStack {
                    Text("Select relay(s)")
                    Spacer()
                    Text("\(selectedRelayCount)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Content relays")
        } footer: {
            Text("Used when everyone on selected relays is selected. Blocked accounts and muted content are always hidden.")
        }
        .onChange(of: draft.mediaRelays) { _ in
            if selectedRelayCount == 0 && draft.mediaSource == .selectedRelays {
                draft.mediaSource = .follows
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: MediaFeedSource, title: String, description: String) -> some View {
        Button {
            draft.mediaSource = source
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: draft.mediaSource == source ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.mediaSource == source ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
