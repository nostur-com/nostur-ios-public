//
//  LearnedWoTView.swift
//  Nostur
//

import SwiftUI

struct LearnedWoTView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var store = LearnedWoTStore.shared
    @State private var searchText = ""
    @State private var showClearConfirmation = false

    private var filteredEntries: [LearnedWoTEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            entry.pubkey.localizedCaseInsensitiveContains(query)
                || NRContact.instance(of: entry.pubkey).anyName.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            if store.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No learned contacts yet")
                        .font(.headline)
                    Text("People you reply or react to will appear here automatically.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(theme.listBackground)
            }
            else {
                ForEach(filteredEntries) { entry in
                    LearnedWoTRow(entry: entry)
                        .listRowBackground(theme.listBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.remove(entry.pubkey)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(theme.listBackground)
        .searchable(text: $searchText, prompt: "Search learned contacts")
        .navigationTitle("Learned Web of Trust")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.entries.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear Learned Web of Trust")
                }
            }
        }
        .confirmationDialog(
            "Clear Learned Web of Trust?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                store.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("People already included through follows remain in your Web of Trust.")
        }
    }
}

private struct LearnedWoTRow: View {
    let entry: LearnedWoTEntry
    @ObservedObject private var nrContact: NRContact

    init(entry: LearnedWoTEntry) {
        self.entry = entry
        nrContact = NRContact.instance(of: entry.pubkey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NRProfileRow(withoutFollowButton: true, nrContact: nrContact)

            HStack(spacing: 5) {
                Text(interactionDescription)
                Text("·")
                Text(entry.lastInteractionAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 58)
        }
        .padding(.vertical, 4)
    }

    private var interactionDescription: String {
        let kinds = entry.interactionKinds
        if kinds.contains(.reply) && kinds.contains(.reaction) {
            return String(localized: "Replies and reactions")
        }
        if kinds.contains(.reply) {
            return String(localized: "Replies")
        }
        return String(localized: "Reactions")
    }
}
