//
//  ProfileMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

// MEDIA ON USER PROFILE SCREEN
struct ProfileMediaView: View {
    @Environment(\.availableWidth) private var availableWidth
    public let pubkey: String
    @StateObject private var vm = ProfileGalleryViewModel()
    
    private static let initialColumns = 3
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: initialColumns)

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                .task(id: "profilegallery") {
                    vm.load(pubkey)
                    do {
                        try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                        
                        Task { @MainActor in
                            if vm.state == .loading || vm.state == .initializing {
                                vm.state = .timeout
                            }
                        }
                    } catch { }
                }
        case .ready:
            if !vm.items.isEmpty {
                // No longer LazyVGrid here, because in List its not Lazy. We can just make 3 by 1 rows here, container List will make it lazy.
                ForEach(Array(stride(from: 0, to: vm.items.count, by: 3)), id: \.self) { index in
                    HStack(spacing: GUTTER) {
                        Group {
                            GalleryGridItemView(size: ((availableWidth - GUTTER*2) / 3.0), items: vm.items, currentIndex: index)
                                .task {
                                    vm.fetchMoreIfNeeded(index)
                                }
                            
                            if (index+1) < vm.items.count {
                                GalleryGridItemView(size: ((availableWidth - GUTTER*2) / 3.0), items: vm.items, currentIndex: index + 1)
                            }
                            if (index+2) < vm.items.count {
                                GalleryGridItemView(size: ((availableWidth - GUTTER*2) / 3.0), items: vm.items, currentIndex: index + 2)
                            }
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: ((availableWidth - GUTTER*2) / 3.0), height: ((availableWidth - GUTTER*2) / 3.0))
                        .clipped()
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.bottom, GUTTER)
                    }
                }
            }
            else {
                Button("Refresh") { vm.reload(pubkey) }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            } 
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch content")
                Button("Try again") { vm.reload(pubkey) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

import NavigationBackport

struct ProfileMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadMedia()
        }) {
            NBNavigationStack {
                List {
                    Section {
                        ProfileMediaView(pubkey: pubkey)
                    }
                    .listRowSpacing(10.0)
                    .listRowInsets(EdgeInsets())
                    .listSectionSeparator(.hidden)
                    .listRowSeparator(.hidden)
                }
                .listRowSpacing(10.0)
                .listStyle(.plain)
            }
        }
    }
}
