//
//  AvailableWidthContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2024.
//

import SwiftUI

struct AvailableWidthContainer<Content: View>: View {
    
    @StateObject private var dim = DIMENSIONS()
    
    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        GeometryReader { geo in
            content
                .onAppear(perform: {
                    dim.listWidth = geo.size.width
                    L.og.debug("dim.listWidth = \(geo.size.width)")
                })
        }
        .environmentObject(dim)
    }
}
