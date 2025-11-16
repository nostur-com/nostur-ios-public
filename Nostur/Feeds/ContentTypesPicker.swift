//
//  ContentTypesPicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/11/2025.
//

import SwiftUI
import NavigationBackport

let VIDEO_TYPES: Set<Int> = [21,22,34235,34236]

enum ContentKind: CaseIterable, Identifiable {
    case photos
    case normalVideos
    case shortVideos
    case voiceMessages
    case highlights
    
    // The raw integer IDs for each case
    var ids: Set<Int> {
        switch self {
        case .photos: return [20]
        case .normalVideos: return [21, 34235]
        case .shortVideos:  return [22, 34236]
        case .voiceMessages:  return [1222, 1244]
        case .highlights:  return [9802]
        }
    }
    
    // MARK: - Identifiable
    var id: Self { self }   // the enum case itself is the identifier
    
    // MARK: - CaseIterable (automatically synthesised, but we expose it)
    static var all: [ContentKind] = [.photos, .normalVideos, .shortVideos, .highlights, .voiceMessages]
}

func kindsDescription(_ kinds: Set<Int>) -> String {
    var kindsDescription: Set<String> = []
    
    if kinds.contains(20) {
        kindsDescription.insert(String(localized: "Photos"))
    }
    if kinds.contains(21) {
        kindsDescription.insert(String(localized: "Videos"))
    }
    if kinds.contains(22) {
        kindsDescription.insert(String(localized: "Short videos"))
    }
    if kinds.contains(9802) {
        kindsDescription.insert(String(localized: "Highlights"))
    }
    if kinds.contains(1222) {
        kindsDescription.insert(String(localized: "Voice Messages"))
    }
    return kindsDescription.joined(separator: ", ")
}


struct ContentTypesPicker: View {
    @Binding var selectedKinds: Set<Int>
    
    @State var selectedContentTypes: Set<ContentKind> = []
    
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) var dismiss
        
    var body: some View {
        NXForm {
            Section(header: Text("Content types", comment: "Header for a feed setting")) {
                HStack {
                    Image(systemName: selectedContentTypes.contains(.photos) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedContentTypes.contains(.photos) ? Color.primary : Color.secondary)
                    Text("Photos")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(.photos)
                }
                
                HStack {
                    Image(systemName: selectedContentTypes.contains(.normalVideos) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedContentTypes.contains(.normalVideos) ? Color.primary : Color.secondary)
                    Text("Videos")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(.normalVideos)
                }
                
                HStack {
                    Image(systemName: selectedContentTypes.contains(.shortVideos) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedContentTypes.contains(.shortVideos) ? Color.primary : Color.secondary)
                    Text("Short Videos (Vines)")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(.shortVideos)
                }
                
                HStack {
                    Image(systemName: selectedContentTypes.contains(.highlights) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedContentTypes.contains(.highlights) ? Color.primary : Color.secondary)
                    Text("Highlights")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(.highlights)
                }
                
                HStack {
                    Image(systemName: selectedContentTypes.contains(.voiceMessages) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedContentTypes.contains(.voiceMessages) ? Color.primary : Color.secondary)
                    Text("Voice Messages (Yaks)")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggle(.voiceMessages)
                }
            }
        }
        .navigationTitle("Select content types")
        .navigationBarTitleDisplayMode(.inline)
        
        .onAppear {
            if selectedKinds.contains(20) {
                selectedContentTypes.insert(ContentKind.photos)
            }
            if selectedKinds.contains(21) {
                selectedContentTypes.insert(ContentKind.normalVideos)
            }
            if selectedKinds.contains(22) {
                selectedContentTypes.insert(ContentKind.shortVideos)
            }
            if selectedKinds.contains(9802) {
                selectedContentTypes.insert(ContentKind.highlights)
            }
            if selectedKinds.contains(1222) {
                selectedContentTypes.insert(ContentKind.voiceMessages)
            }
        }
    }
    
    private func toggle(_ contenType: ContentKind) {
        if selectedContentTypes.contains(contenType) {
            selectedContentTypes.remove(contenType)
            selectedKinds = selectedKinds.subtracting(contenType.ids)
        }
        else {
            selectedContentTypes.insert(contenType)
            selectedKinds = selectedKinds.union(contenType.ids)
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var selectedRelays: Set<CloudRelay> = []
    PreviewContainer({ pe in
        pe.loadRelays()
    }) {
        NBNavigationStack {
            if let feed = PreviewFetcher.fetchCloudFeed() {
                FeedRelaysPicker(selectedRelays: $selectedRelays)
                .withNavigationDestinations()
            }
        }
    }
}
