//
//  HotColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//

import SwiftUI

struct HotColumn: View {
    
    @StateObject private var vm = HotViewModel()
    
    var body: some View {
        Hot()
            .environmentObject(vm)
    }
}

#Preview {
    HotColumn()
}
