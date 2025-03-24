//
//  WithNavigationIf.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2025.
//

import SwiftUI
import NavigationBackport

struct WithNavigationIf<Content: View>: View {
    
    let condition: Bool
    let content: Content
        
    init(condition: Bool, @ViewBuilder _ content: () -> Content) {
        self.condition = condition
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            if condition {
                NBNavigationStack {
                    content
                }
            }
            else {
                content
            }
        }
    }
}
