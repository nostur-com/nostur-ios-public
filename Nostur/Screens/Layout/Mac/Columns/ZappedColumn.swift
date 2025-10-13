//
//  ZappedColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI

struct ZappedColumn: View {
    
    @StateObject private var vm = ZappedViewModel()
    
    var body: some View {
        Zapped()
            .environmentObject(vm)
    }
}

#Preview {
    ZappedColumn()
}
