//
//  Container.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/06/2025.
//

import SwiftUI

struct Container<Content: View>: View {
    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
    }
}
