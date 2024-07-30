//
//  AvailableWidthContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2024.
//

import SwiftUI

struct AvailableWidthContainer<Content: View>: View {
    
    @StateObject private var dim = DIMENSIONS()
    
    // Need this or .listWidth won't be set until next resize
    @State private var ready = false
    
    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        GeometryReader { geo in
            if ready {
                content
                    .environmentObject(dim)
            }
            else {
                Color.clear
                    .frame(height: 1)
                    .onAppear(perform: {
                        ready = true
                        dim.listWidth = geo.size.width
                    })
            }
        }
        
    }
}
