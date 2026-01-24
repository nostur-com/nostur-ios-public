//
//  StreamsColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//


import SwiftUI
import NavigationBackport

struct StreamsColumn: View {
    @StateObject private var vm = StreamsViewModel()

    var body: some View {
        Streams()
            .environmentObject(vm)
    }
}

#Preview {
    StreamsColumn()
}
