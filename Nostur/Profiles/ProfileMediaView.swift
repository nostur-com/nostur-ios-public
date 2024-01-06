//
//  ProfileMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

// MEDIA ON USER PROFILE SCREEN
struct ProfileMediaView: View {
    @StateObject private var vm:ProfileGalleryViewModel
    
    init(pubkey: String) {
        _vm = StateObject(wrappedValue: ProfileGalleryViewModel(pubkey))
    }
    
    private static let initialColumns = 3
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: initialColumns)
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
            switch vm.state {
            case .initializing, .loading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task(id: "profilegallery") {
                        do {
                            try await Task.sleep(
                                until: .now + .seconds(10),
                                tolerance: .seconds(2),
                                clock: .continuous
                            )
                            vm.state = .timeout
                        } catch {
                            
                        }
                    }
            case .ready:
                if !vm.items.isEmpty {
                    if #available(iOS 17, *) {
                        LazyVGrid(columns: gridColumns) {
                            ForEach(vm.items.indices, id:\.self) { index in
                                GeometryReader { geo in
                                    GridItemView17(size: geo.size.width, item: vm.items[index])
                                }
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
                            ForEach(vm.items) { item in
                                GeometryReader { geo in
                                    GridItemView(size: geo.size.width, item: item)
                                }
                                .clipped()
                                .aspectRatio(1, contentMode: .fit)
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
        .onAppear {
            vm.load()
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
                ProfileMediaView(pubkey: pubkey)
            }
        }
    }
}
