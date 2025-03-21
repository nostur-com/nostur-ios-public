//
//  NRNavigationStack.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI
import NavigationBackport

struct NRNavigationStack<Content: View>: View {

    @ViewBuilder
    public let content: Content
    
    var body: some View {
        NBNavigationStack {
            AppEnvironment {
                content
            }       
        }
        .nbUseNavigationStack(.never)
    }
}
