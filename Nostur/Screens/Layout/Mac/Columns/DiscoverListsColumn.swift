//
//  DiscoverListsColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI

struct DiscoverListsColumn: View {
    
    @StateObject private var vm = DiscoverListsViewModel()
    
    var body: some View {
        DiscoverLists()
            .environmentObject(vm)
    }
}

#Preview {
    DiscoverListsColumn()
}
