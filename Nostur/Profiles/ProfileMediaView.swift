//
//  ProfileMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

// MEDIA ON USER PROFILE SCREEN
struct ProfileMediaView: View {
    private static let MAX_IMAGES_PER_POST = 10
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var dim:DIMENSIONS
    let pubkey:String
    @StateObject var vm:ProfileGalleryViewModel
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _vm = StateObject(wrappedValue: ProfileGalleryViewModel(pubkey))
    }
    
    private static let initialColumns = 3
    @State private var gridColumns = Array(repeating: GridItem(.flexible()), count: initialColumns)
    
    var body: some View {
        VStack(spacing: 0) {
            switch vm.state {
            case .initializing:
                EmptyView()
            case .loading:
                CenteredProgressView()
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
                LazyVGrid(columns: gridColumns) {
                    ForEach(vm.items) { item in
                        GeometryReader { geo in
                            GridItemView(size: geo.size.width, item: item)
                        }
                        .clipped()
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
            case .timeout:
                VStack(alignment: .center) {
                    Spacer()
                    Text("Time-out while loading gallery")
                    Button("Try again") { vm.reload() }
                    Spacer()
                }
            }
        }
        .onAppear {
            vm.load()
        }
//        .padding(10)
  
    }
}

struct ProfileMediaView_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadMedia()
        }) {
            NavigationStack {
                ProfileMediaView(pubkey: pubkey)
            }
        }
    }
}
