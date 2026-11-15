//
//  AppDetail.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/01/2024.
//

import CoreData
import SwiftUI
import NukeUI

struct AppDetail: View {
    enum Action {
        case open(URL)
        case profile(Pubkey)
    }

    private struct Person: Identifiable {
        let id: Pubkey
        let name: String
        let pictureURL: URL?
    }

    private struct Connections {
        let followsPublisher: Bool
        let people: [Person]
    }

    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @State private var connections: Connections?

    let app: SuggestedApp
    let onDismiss: (Action?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if let description = app.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(theme.secondary)
                    }

                    if let connections {
                        connectionDetails(connections)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                onDismiss(.open(app.openUrl))
            } label: {
                Text("Open in \(app.name)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NosturButton(height: 36))
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Dismiss", systemImage: "xmark", role: .cancel) { onDismiss(nil) }
            }
        }
        .task(id: app.publisher) {
            let result = await loadConnections()
            guard !Task.isCancelled else { return }
            connections = result
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !settings.lowDataMode, let logoURL = app.logoUrl {
                LazyImage(url: logoURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .pipeline(ImageProcessing.shared.content)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading) {
                Text(app.name).fontWeight(.bold)
                if let host = app.openUrl.host {
                    Text(host)
                        .font(.subheadline)
                        .foregroundColor(theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func connectionDetails(_ connections: Connections) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if connections.followsPublisher {
                Text("You follow the app publisher.")
                    .font(.caption)
            }
            if !connections.people.isEmpty {
                Text("App publisher followed by")
                    .font(.caption.weight(.semibold))
            }

            ForEach(connections.people) { person in
                Button {
                    onDismiss(.profile(person.id))
                } label: {
                    HStack(spacing: 8) {
                        MiniPFP(pictureUrl: settings.lowDataMode ? nil : person.pictureURL, size: 24)
                            .accessibilityHidden(true)
                        Text(person.name).lineLimit(1)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func loadConnections() async -> Connections {
        let follows = AccountsState.shared.loggedInAccount?.followingPublicKeys ?? []
        let publisher = app.publisher
        let followsPublisher = publisher.map { follows.contains($0) } ?? false
        let context = bg()

        return await context.perform {
            var people: Set<Pubkey> = []
            if let publisher, !follows.isEmpty {
                let request = Event.fetchRequest()
                request.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@ AND mostRecentId == nil", follows)
                request.sortDescriptors = [
                    NSSortDescriptor(keyPath: \Event.created_at, ascending: false),
                    NSSortDescriptor(keyPath: \Event.id, ascending: true)
                ]
                request.fetchBatchSize = 50
                var seenAuthors: Set<Pubkey> = []
                for list in (try? context.fetch(request)) ?? [] {
                    guard seenAuthors.insert(list.pubkey).inserted else { continue }
                    if list.fastPs.contains(where: { $0.1 == publisher }) {
                        people.insert(list.pubkey)
                    }
                }
            }

            var profiles: [Pubkey: Person] = [:]
            if !people.isEmpty {
                for contact in Contact.fetchByPubkeys(people, context: context) {
                    profiles[contact.pubkey] = Person(id: contact.pubkey, name: contact.anyName, pictureURL: contact.pictureUrl)
                }
            }
            let namedPeople = people.map { pubkey in
                profiles[pubkey] ?? Person(id: pubkey, name: String(pubkey.suffix(11)), pictureURL: nil)
            }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
            return Connections(followsPublisher: followsPublisher, people: namedPeople)
        }
    }
}

#Preview {
    AppDetail(app: SuggestedApp(
        id: "1", name: "Nostur", description: "A Nostr client",
        openUrl: URL(string: "https://nostur.com")!
    ), onDismiss: { _ in })
    .padding()
}
