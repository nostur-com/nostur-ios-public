//
//  Zoomable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI

struct Zoomable<Content: View>: View {
    @StateObject private var screenSpace: ScreenSpace = .shared
    
    private let content: Content
    
    @State private var screenSize: CGSize = .zero
    
    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                content
            }
            .onAppear {
                screenSize = geometry.size
                screenSpace.screenSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                screenSize = newSize
                screenSpace.screenSize = newSize
            }
        }
    }
}

class ScreenSpace: ObservableObject {
    @Published var screenSize: CGSize = UIScreen.main.bounds.size
    
    static let shared = ScreenSpace()
    private init() { }
}
