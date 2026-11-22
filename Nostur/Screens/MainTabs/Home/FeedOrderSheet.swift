import SwiftUI
import NavigationBackport

struct FeedOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Binding var storedOrder: String
    let availableFeeds: [FeedSwipeSelection]
    let customFeedNames: [String: String]

    private var orderedFeeds: [FeedSwipeSelection] {
        FeedMenuOrder(rawValue: storedOrder).ordered(availableFeeds)
    }

    var body: some View {
        NBNavigationStack {
            NXForm {
                Section {
                    ForEach(orderedFeeds) { feed in
                        FeedMenuLabel(feed: feed, customName: customFeedNames[feed.listId ?? ""])
                    }
                    .onMove { indices, destination in
                        var feeds = orderedFeeds
                        feeds.move(fromOffsets: indices, toOffset: destination)
                        storedOrder = FeedMenuOrder(rawValue: storedOrder).reordering(feeds).rawValue
                    }
                } header: {
                    Text("Feed Order", comment: "Heading above the draggable feeds")
                } footer: {
                    Text("Drag feeds into the order you prefer. This order is used in the menu and when swiping between feeds.")
                }

                Section {
                    Button("Reset Feed Order") {
                        storedOrder = "[]"
                    }
                    .disabled(FeedMenuOrder(rawValue: storedOrder).ids.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(Text("Reorder Feeds"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .presentationBackgroundCompat(theme.listBackground)
    }
}

/// Shared labels keep the title menu and its order editor consistent.
struct FeedMenuLabel: View {
    let feed: FeedSwipeSelection
    var customName: String? = nil

    var body: some View {
        switch feed.tab {
        case "Following": Label("Following", systemImage: "person.circle")
        case "Picture": Label("Photos", systemImage: "photo")
        case "Yak": Label("Yaks", systemImage: "waveform.circle")
        case "Vine":
            if #available(iOS 17.0, *) {
                Label("Divines", systemImage: "person.crop.square.badge.video")
            } else {
                Label("Divines", systemImage: "video.bubble.left")
            }
        case "Streams": Label("Live Streams", systemImage: "dot.radiowaves.left.and.right")
        case "List": Label { Text(verbatim: customName ?? "(no title)") } icon: { Image(systemName: "star") }
        case "Emoji":
            Label { Text("Funny") } icon: {
                Image("LaughterIcon").renderingMode(.template)
            }
        case "Zapped": Label("Zapped", systemImage: "bolt")
        case "Hot": Label("Hot", systemImage: "flame")
        case "DiscoverLists": Label("Follow Packs & Lists", systemImage: "person.2.crop.square.stack")
        case "Gallery": Label("Gallery", systemImage: "photo.on.rectangle.angled")
        case "Explore": Label("Explore", systemImage: "binoculars")
        case "Articles": Label("Reads", systemImage: "newspaper")
        default: Text(verbatim: feed.tab)
        }
    }
}
