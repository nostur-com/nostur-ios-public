//
//  ProfileMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

// MEDIA ON USER PROFILE SCREEN
struct ProfileMediaView: View {
    @StateObject private var vm: ProfileGalleryViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileGalleryViewModel(pubkey))
    }
    @EnvironmentObject private var dim: DIMENSIONS
    
    private static let initialColumns = 3
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: initialColumns)
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        switch vm.state {
        case .initializing, .loading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 700.0, alignment: .top)
                .task(id: "profilegallery") {
                    vm.load()
                    do {
                        try await Task.sleep(nanoseconds: UInt64(10) * NSEC_PER_SEC)
                        if vm.state == .initializing || vm.state == .loading {
                            vm.state = .timeout
                        }
                    } catch { }
                }
        case .ready:
            if !vm.items.isEmpty {
                if #available(iOS 17, *) {
                    LazyVGrid(columns: gridColumns) {
                        ForEach(vm.items.indices, id:\.self) { index in
                            GridItemView17(size: ((dim.listWidth / 3.0) - 20.0), item: vm.items[index])
                                .onBecomingVisible {
                                    vm.fetchMoreIfNeeded(index)
                                }
                                .aspectRatio(contentMode: .fill)
                                .frame(width: ((dim.listWidth / 3.0) - 20.0), height: ((dim.listWidth / 3.0) - 20.0))
                                .clipped()
                                .aspectRatio(1, contentMode: .fit)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sendNotification(.fullScreenView17, FullScreenItem17(items: vm.items, index: index))
                                }
                           
                        }
                    }
                }
                else {
                    LazyVGrid(columns: gridColumns) {
                        ForEach(vm.items.indices, id:\.self) { index in
                            GridItemView(size: ((dim.listWidth / 3.0) - 20.0), item: vm.items[index])
                                .onBecomingVisible {
                                    vm.fetchMoreIfNeeded(index)
                                }
                                .clipped()
                                .aspectRatio(1, contentMode: .fit)
                                .id(index)
                        }
                    }
                }
            }
            else {
                Button("Refresh") { vm.reload() }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .timeout:
            VStack(alignment: .center) {
                Text("Unable to fetch content")
                Button("Try again") { vm.reload() }
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
