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
    
    private let id: String // id is passed to DIMENSIONS so we can do different things based in which id ("context") we are (if dim.id == ....)
    private let content: Content
    
    init(id: String = "Default", @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geo in
            if ready {
                content
                    .environmentObject(dim)
                    .onChange(of: geo.size.width) { newWidth in
                        if dim.listWidth != newWidth {
                            dim.listWidth = newWidth
                        }
                    }
            }
            else {
                Color.clear
                    .frame(height: 1)
                    .onAppear(perform: {
                        ready = true
                        dim.id = self.id
                        dim.listWidth = geo.size.width
                    })
            }
        }
        
    }
}
