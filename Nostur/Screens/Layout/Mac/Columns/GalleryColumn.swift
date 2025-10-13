//
//  GalleryColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI

struct GalleryColumn: View {
    
    @StateObject private var vm = GalleryViewModel()
    
    var body: some View {
        Gallery()
            .environmentObject(vm)
    }
}

#Preview {
    GalleryColumn()
}
