//
//  AvailableWidthContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2024.
//

import SwiftUI

struct AvailableWidthContainer<Content: View>: View {
    
    @State private var availableWidth: CGFloat = UIScreen.main.bounds.width
    
    // Need this or .availableWidth won't be set until next resize
    @State private var ready = false

    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geo in
            if ready {
                content
                    .environment(\.availableWidth, availableWidth)
                    .onChange(of: geo.size.width) { newWidth in
                        if availableWidth != newWidth {
                            availableWidth = newWidth
                        }
                    }
            }
            else {
                Color.clear
                    .frame(height: 1)
                    .onAppear(perform: {
                        ready = true
                        availableWidth = geo.size.width
                    })
            }
        }
        
    }
}
