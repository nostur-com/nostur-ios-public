//
//  EmojiColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//


import SwiftUI

struct EmojiColumn: View {
    
    @StateObject private var vm = EmojiFeedViewModel()
    
    var body: some View {
        EmojiFeed()
            .environmentObject(vm)
    }
}

#Preview {
    EmojiColumn()
}
